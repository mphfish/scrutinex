defmodule Scrutinex.Validator do
  @moduledoc false

  alias Scrutinex.{Column, Check, Coercion, Error, Result}
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

    {coerced_rows, errors, _error_count} =
      data
      |> Enum.with_index()
      |> Enum.reduce_while({[], [], 0}, fn {row, row_idx}, {rows_acc, errors_acc, err_count} ->
        {row_errors, coerced_row} =
          safe_validate_row(
            row,
            row_idx,
            resolved_columns,
            schema,
            col_names_set,
            required_col_names
          )

        new_count = err_count + length(row_errors)
        acc = {[coerced_row | rows_acc], [row_errors | errors_acc], new_count}

        if max_errors != :infinity and new_count >= max_errors do
          {:halt, acc}
        else
          {:cont, acc}
        end
      end)

    errors = errors |> Enum.reverse() |> List.flatten()
    coerced_rows = Enum.reverse(coerced_rows)

    cross_errors = run_all_cross_checks(coerced_rows, schema.checks)

    all_errors = errors ++ cross_errors

    %Result{
      valid?: all_errors == [],
      data: coerced_rows,
      errors: all_errors
    }
  end

  defp safe_validate_row(row, row_idx, columns, schema, col_names_set, required_col_names) do
    validate_row(row, row_idx, columns, schema, col_names_set, required_col_names)
  rescue
    e ->
      error = %Error{
        row: row_idx,
        column: nil,
        check: :internal_error,
        message: "row validation failed: #{Exception.message(e)}",
        metadata: %{kind: :exception},
        value: nil
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

      Enum.flat_map(columns, fn col ->
        case col.name do
          %Regex{} = regex ->
            all_keys
            |> Enum.filter(fn key -> is_binary(key) and Regex.match?(regex, key) end)
            |> Enum.map(fn key -> %Column{col | name: key} end)

          name when is_binary(name) ->
            [col]
        end
      end)
    else
      columns
    end
  end

  defp validate_row(row, row_idx, columns, schema, col_names_set, required_col_names) do
    presence_errors = check_presence(row, row_idx, required_col_names)

    strict_errors =
      if schema.strict do
        check_strict(row, row_idx, col_names_set)
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
        value: nil
      }
    end
  end

  defp check_strict(row, row_idx, declared_set) do
    for key <- Map.keys(row), not MapSet.member?(declared_set, key) do
      %Error{
        row: row_idx,
        column: key,
        check: :unexpected_column,
        message: "unexpected column",
        metadata: %{column: key},
        value: nil
      }
    end
  end

  # raw_value is the original value from the row, used by the :skip branch.
  # In the with/else, :skip is returned by check_null (before maybe_coerce
  # rebinds value), so the else clause correctly sees the original value.
  defp validate_cell(row, col, row_idx, errors) do
    raw_value = Map.get(row, col.name)

    with :ok <- check_null(raw_value, col, row_idx),
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
            value: value
          }

          {:error, error, value}
      end
    else
      {:ok, value}
    end
  end

  defp check_null(value, col, row_idx) do
    is_empty = is_nil(value) or value == ""

    if is_empty do
      if col.nullable do
        :skip
      else
        error = %Error{
          row: row_idx,
          column: col.name,
          check: :not_null,
          message: "must not be empty",
          metadata: %{column: col.name},
          value: value
        }

        {:error, error, value}
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
            value: value
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
            error = %Error{
              row: row_idx,
              column: col.name,
              check: check_type,
              message: message,
              metadata: metadata,
              value: value
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
    Enum.reduce(checks, acc, fn %Check{name: name, message: message, function: func}, acc ->
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
              value: nil
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
              value: nil
            }
            | acc
          ]
      end
    end)
  end
end
