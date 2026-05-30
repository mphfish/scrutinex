defmodule Scrutinex.Validator do
  @moduledoc false

  alias Scrutinex.{Column, Check, Coercion, Error, Result, Index}
  alias Scrutinex.Checks.{Number, Inclusion, Exclusion, Format, Length, Custom}

  @doc """
  Runs the full validation pipeline on `data` against `schema`.

  Pipeline steps:

  1. Resolve regex column patterns against actual data keys
  2. For each row: check required presence, strict-mode violations, then
     per-cell null check, coercion, type check, and column checks
  3. Run cross-column checks on the (possibly coerced) rows
  4. Collect all errors into a `Scrutinex.Result`
  """
  @spec validate(list(map()), Scrutinex.Schema.Definition.t(), keyword()) :: Result.t()
  def validate(data, schema, opts \\ []) do
    max_errors = Keyword.get(opts, :max_errors, :infinity)
    resolved_columns = resolve_columns(schema.columns, data)

    col_names_set = MapSet.new(resolved_columns, & &1.name)
    required_col_names = for col <- resolved_columns, col.required, do: col.name

    declared_string_names = for col <- schema.columns, is_binary(col.name), do: col.name

    suggestion_map =
      build_suggestion_map(data, schema.strict, declared_string_names, col_names_set)

    {coerced_rows, errors_rev} =
      data
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {row, row_idx}, errors_acc ->
        {row_errors, coerced_row} =
          safe_validate_row(
            row,
            row_idx,
            resolved_columns,
            schema,
            col_names_set,
            required_col_names,
            suggestion_map
          )

        {coerced_row, [row_errors | errors_acc]}
      end)

    errors = errors_rev |> Enum.reverse() |> List.flatten()

    cross_errors = run_all_cross_checks(coerced_rows, schema.checks)
    invalid_cells = invalid_index_cells(errors)
    unique_errors = run_unique_indexes(coerced_rows, schema.indexes, invalid_cells)

    regex_errors = check_required_regex(schema.columns, resolved_columns)
    all_errors = regex_errors ++ errors ++ cross_errors ++ unique_errors

    %Result{
      valid?: not Enum.any?(all_errors, &(&1.severity == :error)),
      data: coerced_rows,
      errors: limit_errors(all_errors, max_errors)
    }
  end

  # max_errors caps only the returned error list; validation always runs to
  # completion, so valid? above reflects the full dataset. When capping, keep
  # :error-severity entries ahead of :warning entries (each in natural order) so
  # a valid?: false verdict is always accompanied by at least one :error here.
  defp limit_errors(entries, :infinity), do: entries

  defp limit_errors(entries, max_errors) do
    {errors, warnings} = Enum.split_with(entries, &(&1.severity == :error))
    Enum.take(errors ++ warnings, max_errors)
  end

  defp safe_validate_row(
         row,
         row_idx,
         columns,
         schema,
         col_names_set,
         required_col_names,
         suggestion_map
       ) do
    validate_row(row, row_idx, columns, schema, col_names_set, required_col_names, suggestion_map)
  rescue
    e ->
      error = %Error{
        row: row_idx,
        column: nil,
        check: :internal_error,
        message: "row validation failed: #{Exception.message(e)}",
        metadata: %{kind: :exception},
        value: nil,
        severity: :error
      }

      {[error], row}
  end

  defp resolve_columns(columns, data) do
    has_regex = Enum.any?(columns, fn col -> match?(%Regex{}, col.name) end)

    if has_regex do
      all_keys =
        Enum.reduce(data, MapSet.new(), fn row, acc ->
          row |> Map.keys() |> Enum.reduce(acc, &MapSet.put(&2, &1))
        end)

      Enum.flat_map(columns, fn %Column{} = col ->
        case col.name do
          %Regex{} = regex ->
            all_keys
            |> Enum.filter(fn key -> is_binary(key) and Regex.match?(regex, key) end)
            |> Enum.map(fn key -> %Column{} = %{col | name: key} end)

          name when is_binary(name) ->
            [col]
        end
      end)
    else
      columns
    end
  end

  defp check_required_regex(schema_columns, resolved_columns) do
    schema_columns
    |> Enum.filter(fn col -> match?(%Regex{}, col.name) and col.required end)
    |> Enum.reject(fn col ->
      Enum.any?(resolved_columns, fn rc -> Regex.match?(col.name, rc.name) end)
    end)
    |> Enum.map(fn col ->
      source = Regex.source(col.name)

      %Error{
        row: nil,
        column: source,
        check: :required_columns,
        message: "no columns matched pattern '%{pattern}'",
        metadata: %{pattern: source},
        value: nil,
        severity: :error
      }
    end)
  end

  defp validate_row(
         row,
         row_idx,
         columns,
         schema,
         col_names_set,
         required_col_names,
         suggestion_map
       ) do
    presence_errors = check_presence(row, row_idx, required_col_names)

    strict_errors =
      if schema.strict do
        check_strict(row, row_idx, col_names_set, suggestion_map)
      else
        []
      end

    {cell_errors_rev, coerced_row} =
      Enum.reduce(columns, {[], row}, fn col, {errs, current_row} ->
        case Map.fetch(current_row, col.name) do
          {:ok, _} -> validate_cell(current_row, col, row_idx, errs)
          :error -> {errs, current_row}
        end
      end)

    {presence_errors ++ strict_errors ++ Enum.reverse(cell_errors_rev), coerced_row}
  end

  defp check_presence(row, row_idx, required_col_names) do
    for name <- required_col_names, not Map.has_key?(row, name) do
      %Error{
        row: row_idx,
        column: name,
        check: :required,
        message: "is required",
        metadata: %{column: name},
        value: nil,
        severity: :error
      }
    end
  end

  defp check_strict(row, row_idx, declared_set, suggestion_map) do
    for key <- Map.keys(row), not MapSet.member?(declared_set, key) do
      suggestion = Map.get(suggestion_map, key)
      unexpected_column_error(row_idx, key, suggestion)
    end
  end

  defp unexpected_column_error(row_idx, key, nil) do
    %Error{
      row: row_idx,
      column: key,
      check: :unexpected_column,
      message: "unexpected column",
      metadata: %{column: key},
      value: nil,
      severity: :error
    }
  end

  defp unexpected_column_error(row_idx, key, suggestion) do
    %Error{
      row: row_idx,
      column: key,
      check: :unexpected_column,
      message: "unexpected column — did you mean '%{suggestion}'?",
      metadata: %{column: key, suggestion: suggestion},
      value: nil,
      severity: :error
    }
  end

  @suggestion_threshold 0.8

  defp build_suggestion_map(data, true, declared_string_names, col_names_set)
       when declared_string_names != [] do
    all_data_keys = data |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    all_data_keys
    |> Enum.reject(&MapSet.member?(col_names_set, &1))
    |> Map.new(fn key ->
      {best_name, best_score} =
        declared_string_names
        |> Enum.map(fn name -> {name, String.jaro_distance(key, name)} end)
        |> Enum.max_by(&elem(&1, 1))

      suggestion = if best_score >= @suggestion_threshold, do: best_name, else: nil
      {key, suggestion}
    end)
  end

  defp build_suggestion_map(_data, _strict, _declared_string_names, _col_names_set), do: %{}

  # raw_value is the original value from the row, used by the :skip branch.
  # In the with/else, :skip is returned by check_empty (before maybe_coerce
  # rebinds value), so the else clause correctly sees the original value.
  defp validate_cell(row, col, row_idx, errors) do
    raw_value = Map.get(row, col.name)

    with :ok <- check_empty(raw_value, col, row_idx),
         {:ok, value} <- maybe_coerce(raw_value, col, row_idx),
         :ok <- maybe_type_check(value, col, row_idx),
         :ok <- run_checks(value, col, row_idx) do
      if value === raw_value do
        {errors, row}
      else
        {errors, Map.put(row, col.name, value)}
      end
    else
      :skip ->
        {errors, row}

      {:warn, warning_error} ->
        {[warning_error | errors], Map.put(row, col.name, nil)}

      {:error, error, coerced_value} ->
        if coerced_value === raw_value do
          {[error | errors], row}
        else
          {[error | errors], Map.put(row, col.name, coerced_value)}
        end
    end
  end

  defp maybe_coerce(value, col, row_idx) do
    if col.coerce do
      case Coercion.coerce(value, col.type) do
        {:ok, coerced} ->
          {:ok, coerced}

        {:error, msg} ->
          error = %Error{
            row: row_idx,
            column: col.name,
            check: :coercion,
            message: msg,
            metadata: %{type: col.type},
            value: value,
            severity: col.severity
          }

          {:error, error, value}
      end
    else
      {:ok, value}
    end
  end

  defp check_empty(value, col, row_idx) do
    is_empty = is_nil(value) or value == ""

    if is_empty do
      case col.on_empty do
        :ignore ->
          :skip

        :error ->
          error = %Error{
            row: row_idx,
            column: col.name,
            check: :not_null,
            message: "must not be empty",
            metadata: %{column: col.name},
            value: value,
            severity: col.severity
          }

          {:error, error, value}

        :warn ->
          error = %Error{
            row: row_idx,
            column: col.name,
            check: :empty_value,
            message: "value is empty",
            metadata: %{column: col.name},
            value: value,
            severity: :warning
          }

          {:warn, error}
      end
    else
      :ok
    end
  end

  defp maybe_type_check(value, col, row_idx) do
    if col.coerce or is_nil(value) do
      :ok
    else
      case Coercion.type_check(value, col.type) do
        :ok ->
          :ok

        {:error, msg} ->
          error = %Error{
            row: row_idx,
            column: col.name,
            check: :type,
            message: msg,
            metadata: %{type: col.type},
            value: value,
            severity: col.severity
          }

          {:error, error, value}
      end
    end
  end

  defp run_checks(value, col, row_idx) do
    if is_nil(value) do
      :ok
    else
      Enum.reduce_while(col.checks, :ok, fn {check_type, args}, :ok ->
        case run_check(check_type, value, args) do
          :ok ->
            {:cont, :ok}

          {:error, message, metadata} ->
            severity = Map.get(col.check_severities, check_type, col.severity)

            error = %Error{
              row: row_idx,
              column: col.name,
              check: check_type,
              message: message,
              metadata: metadata,
              value: value,
              severity: severity
            }

            {:halt, {:error, error, value}}
        end
      end)
    end
  end

  defp run_check(:number, value, opts), do: Number.run(value, opts)
  defp run_check(:inclusion, value, list), do: Inclusion.run(value, list)
  defp run_check(:exclusion, value, list), do: Exclusion.run(value, list)
  defp run_check(:format, value, regex), do: Format.run(value, regex)
  defp run_check(:length, value, opts), do: Length.run(value, opts)
  defp run_check(:custom, value, func), do: Custom.run(value, func)

  defp run_check(unknown, _value, _args) do
    raise ArgumentError, "unknown check type: #{inspect(unknown)}"
  end

  defp run_all_cross_checks(coerced_rows, checks) do
    coerced_rows
    |> Enum.with_index()
    |> Enum.reduce([], fn {row, row_idx}, acc ->
      run_cross_column_checks(row, row_idx, checks, acc)
    end)
    |> Enum.reverse()
  end

  defp run_cross_column_checks(row, row_idx, checks, acc) do
    Enum.reduce(
      checks,
      acc,
      fn %Check{name: name, message: message, severity: severity, function: func}, acc ->
        try do
          if func.(row) do
            acc
          else
            [
              %Error{
                row: row_idx,
                column: nil,
                check: name,
                message: message,
                metadata: %{},
                value: nil,
                severity: severity
              }
              | acc
            ]
          end
        rescue
          e ->
            [
              %Error{
                row: row_idx,
                column: nil,
                check: name,
                message: "cross-column check raised: #{Exception.message(e)}",
                metadata: %{kind: :exception},
                value: nil,
                severity: severity
              }
              | acc
            ]
        end
      end
    )
  end

  # Set of {row_index, column} pairs whose value failed coercion or
  # type-checking. Those cells keep their raw (un-coerced) value, so a row is
  # excluded from any index that contains such a column — mirroring the
  # SQL-null skip in build_key/2. A row is only compared on values that
  # successfully coerced to their declared type.
  defp invalid_index_cells(errors) do
    for %Error{check: check, row: row, column: column} <- errors,
        check in [:coercion, :type],
        not is_nil(column),
        into: MapSet.new(),
        do: {row, column}
  end

  defp run_unique_indexes(rows, indexes, invalid_cells) do
    indexed_rows = Enum.with_index(rows)
    Enum.flat_map(indexes, &run_index(&1, indexed_rows, invalid_cells))
  end

  defp run_index(%Index{} = index, indexed_rows, invalid_cells) do
    {errors_rev, _seen} =
      Enum.reduce(indexed_rows, {[], %{}}, &track_row(&1, &2, index, invalid_cells))

    Enum.reverse(errors_rev)
  end

  # A non-map row (malformed input) already carries an :internal_error from the
  # per-row pass; skip it here rather than letting build_key/2 raise BadMapError.
  defp track_row({row, row_idx}, acc, %Index{} = index, invalid_cells) when is_map(row) do
    if Enum.any?(index.columns, &MapSet.member?(invalid_cells, {row_idx, &1})) do
      acc
    else
      case build_key(row, index.columns) do
        :skip -> acc
        {:ok, key} -> record_or_flag(key, row_idx, index, acc)
      end
    end
  end

  defp track_row({_row, _row_idx}, acc, %Index{}, _invalid_cells), do: acc

  defp record_or_flag(key, row_idx, %Index{} = index, {errors, seen}) do
    case Map.fetch(seen, key) do
      {:ok, first_idx} -> {[unique_error(index, row_idx, first_idx, key) | errors], seen}
      :error -> {errors, Map.put(seen, key, row_idx)}
    end
  end

  defp build_key(row, columns) do
    Enum.reduce_while(columns, {:ok, %{}}, fn col, {:ok, acc} ->
      value = Map.get(row, col)

      if is_nil(value) or value == "" do
        {:halt, :skip}
      else
        {:cont, {:ok, Map.put(acc, col, value)}}
      end
    end)
  end

  defp unique_error(%Index{} = index, row_idx, first_idx, values) do
    %Error{
      row: row_idx,
      column: nil,
      check: index.name,
      message: index.message,
      metadata: %{columns: index.columns, first_row: first_idx, values: values},
      value: nil,
      severity: index.severity
    }
  end
end
