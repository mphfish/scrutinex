defmodule Scrutinex.Schema do
  @moduledoc """
  DSL for defining tabular-data validation schemas.

  `use Scrutinex.Schema` (with optional `strict: true`) imports the `column/2`,
  `column/3`, and `check/2`/`check/3` macros and registers a `__schema__/0`
  callback at compile time.

  ## Supported types

  `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`

  ## Column options

    * `:required` - fail if the column key is missing (default `true`)
    * `:coerce` - attempt type casting before validation (default `false`)
    * `:on_empty` - behaviour when a cell is `nil` or `""` (default `:error`):
      - `:error` — severity `:error`, skips remaining checks
      - `:warn` — severity `:warning`, skips remaining checks, cell becomes `nil` in result data
      - `:ignore` — no error, skips remaining checks
    * `:nullable` - accepted as compile-time sugar for `on_empty: :ignore`; cannot be combined with `:on_empty`
    * `:checks` - keyword list of built-in checks:
      - `number: [greater_than: 0, less_than: 100]`
      - `inclusion: ["A", "B", "C"]`
      - `exclusion: ["X"]`
      - `format: ~r/^[A-Z]/`
      - `length: [min: 1, max: 255]`
      - `custom: &my_function/1`

  ## Strict mode

  Pass `strict: true` to `use Scrutinex.Schema` to reject rows that contain
  columns not declared in the schema.

  ## Cross-column checks

  Use the `check` macro to validate relationships between columns. The block
  receives the full row map and must return a truthy value to pass.

  ## Unique indexes

  Use the `unique` macro to require that the tuple of values across one or more
  columns does not repeat across rows (a composite unique index). Pass a list of
  declared column names, or a single name for single-column uniqueness:

      unique ["region", "sku"]      # the (region, sku) pair must be unique
      unique "email"                # email must be unique
      unique ["region", "sku"], name: :region_sku, severity: :warning

  Options: `:name` (atom, default `:unique`; becomes the error `check:` field),
  `:message` (default `"is a duplicate of row %{first_row}"`), and `:severity`
  (`:error` default, or `:warning`).

  Custom `:message` templates can interpolate `%{first_row}`; `:columns` and
  `:values` are available in the error `metadata` for programmatic use.

  The first row with a given tuple is canonical; every later duplicate is flagged
  with `column: nil` and a `metadata` map containing `:columns` (the indexed
  column names), `:first_row` (the zero-based index of the canonical row), and
  `:values` (the duplicated column-to-value map). Rows where
  any indexed column is missing, `nil`, or `""` are excluded (SQL-null
  semantics), as are rows where an indexed column's value failed to coerce or
  type-check to its declared type (such a cell has no valid coerced value to
  compare). Indexed columns must be declared (regex-matched columns are not
  supported).

  ## Trust Boundary

  Schema definitions, including custom check functions and cross-column check
  blocks, are **trusted code**. They execute with the same privileges as your
  application. Do not construct schemas from untrusted user input.

  ## Example

      defmodule MyApp.PeopleSchema do
        use Scrutinex.Schema, strict: true

        column "name",  :string,  checks: [length: [min: 1, max: 100]]
        column "age",   :integer, coerce: true, checks: [number: [greater_than: 0]]
        column "email", :string,  checks: [format: ~r/@/]
        column ~r/^score_/, :float, required: false, on_empty: :ignore

        check :age_name_consistency do
          fn row -> !(row["age"] > 150 && row["name"] == "") end
        end
      end

      result = Scrutinex.validate(data, MyApp.PeopleSchema)
  """

  alias Scrutinex.{Column, Check, Index}

  defmacro __using__(opts) do
    quote do
      Module.register_attribute(__MODULE__, :scrutinex_columns, accumulate: true)
      Module.register_attribute(__MODULE__, :scrutinex_checks, accumulate: true)
      Module.register_attribute(__MODULE__, :scrutinex_indexes, accumulate: true)
      Module.put_attribute(__MODULE__, :scrutinex_strict, unquote(opts[:strict] || false))

      import Scrutinex.Schema,
        only: [column: 2, column: 3, check: 2, check: 3, unique: 1, unique: 2]

      @before_compile Scrutinex.Schema
    end
  end

  defmacro column(name, type, opts \\ []) do
    raw_checks = Keyword.get(opts, :checks, [])
    column_severity = Keyword.get(opts, :severity, :error)

    default_required =
      case name do
        {:sigil_r, _, _} -> false
        _ -> true
      end

    nullable_opt = Keyword.get(opts, :nullable)
    on_empty_opt = Keyword.get(opts, :on_empty)

    on_empty =
      case {nullable_opt, on_empty_opt} do
        {nil, nil} ->
          :error

        {nil, val} ->
          val

        {true, nil} ->
          :ignore

        {false, nil} ->
          :error

        {_, _} ->
          raise CompileError,
            description: "cannot set both :nullable and :on_empty on column #{inspect(name)}"
      end

    # Extract per-check severity overrides at compile time.
    # A check entry like `format: {~r/@/, severity: :warning}` is a 2-tuple
    # where the second element is a keyword list containing :severity.
    # We separate the severity from the check args and store them in check_severities.
    {stripped_checks, check_severities} =
      Enum.reduce(raw_checks, {[], %{}}, fn
        {check_type, {actual_args, per_check_opts}}, {checks_acc, sev_acc}
        when is_list(per_check_opts) ->
          case Keyword.pop(per_check_opts, :severity) do
            {nil, _} ->
              {[{check_type, {actual_args, per_check_opts}} | checks_acc], sev_acc}

            {sev, remaining_opts} ->
              stripped_args =
                if remaining_opts == [] do
                  actual_args
                else
                  {actual_args, remaining_opts}
                end

              {[{check_type, stripped_args} | checks_acc], Map.put(sev_acc, check_type, sev)}
          end

        entry, {checks_acc, sev_acc} ->
          {[entry | checks_acc], sev_acc}
      end)

    stripped_checks = Enum.reverse(stripped_checks)

    quote do
      @scrutinex_columns %Column{
        name: unquote(name),
        type: unquote(type),
        required: unquote(Keyword.get(opts, :required, default_required)),
        coerce: unquote(Keyword.get(opts, :coerce, false)),
        on_empty: unquote(on_empty),
        checks: unquote(stripped_checks),
        severity: unquote(column_severity),
        check_severities: unquote(Macro.escape(check_severities))
      }
    end
  end

  defmacro check(name, opts \\ [], do: block) do
    message = Keyword.get(opts, :message, "check failed")
    severity = Keyword.get(opts, :severity, :error)

    quote do
      @scrutinex_checks {unquote(name), unquote(message), unquote(severity),
                         unquote(Macro.escape(block))}
    end
  end

  defmacro unique(columns, opts \\ []) do
    name = Keyword.get(opts, :name, :unique)
    message = Keyword.get(opts, :message, "is a duplicate of row %{first_row}")
    severity = Keyword.get(opts, :severity, :error)

    quote do
      @scrutinex_indexes %Index{
        name: unquote(name),
        columns: List.wrap(unquote(columns)),
        message: unquote(message),
        severity: unquote(severity)
      }
    end
  end

  @valid_types [:string, :integer, :float, :boolean, :date, :datetime]
  @valid_checks [:number, :inclusion, :exclusion, :format, :length, :custom]

  defmacro __before_compile__(env) do
    columns = Module.get_attribute(env.module, :scrutinex_columns) |> Enum.reverse()
    checks_raw = Module.get_attribute(env.module, :scrutinex_checks) |> Enum.reverse()
    indexes = Module.get_attribute(env.module, :scrutinex_indexes) |> Enum.reverse()
    strict = Module.get_attribute(env.module, :scrutinex_strict)

    for %Column{type: type, name: name, checks: checks, on_empty: on_empty} <- columns do
      unless type in @valid_types do
        raise CompileError,
          description:
            "invalid column type #{inspect(type)} for column #{inspect(name)}. " <>
              "Must be one of: #{inspect(@valid_types)}"
      end

      unless on_empty in [:error, :warn, :ignore] do
        raise CompileError,
          description:
            "invalid on_empty value #{inspect(on_empty)} for column #{inspect(name)}. " <>
              "Must be one of: [:error, :warn, :ignore]"
      end

      for {check_name, _} <- checks do
        unless check_name in @valid_checks do
          raise CompileError,
            description:
              "unknown check #{inspect(check_name)} for column #{inspect(name)}. " <>
                "Must be one of: #{inspect(@valid_checks)}"
        end
      end
    end

    declared_string_names =
      for(%Column{name: n} <- columns, is_binary(n), into: MapSet.new(), do: n)

    Enum.each(indexes, &validate_index!(&1, declared_string_names))

    checks =
      Enum.map(checks_raw, fn {name, message, severity, func_ast} ->
        quote do
          %Check{
            name: unquote(name),
            message: unquote(message),
            severity: unquote(severity),
            function: unquote(func_ast)
          }
        end
      end)

    escaped_columns = Macro.escape(columns)
    escaped_indexes = Macro.escape(indexes)

    quote do
      @doc "Returns the schema definition for this module."
      @spec __schema__() :: Scrutinex.Schema.Definition.t()
      def __schema__ do
        %Scrutinex.Schema.Definition{
          columns: unquote(escaped_columns),
          checks: unquote(checks),
          indexes: unquote(escaped_indexes),
          strict: unquote(strict)
        }
      end
    end
  end

  defp validate_index!(%Index{name: name, columns: cols, severity: severity}, declared) do
    unless is_list(cols) and cols != [] and Enum.all?(cols, &is_binary/1) do
      raise CompileError,
        description:
          "unique index #{inspect(name)} must specify a non-empty list of " <>
            "string column names, got: #{inspect(cols, charlists: :as_lists)}"
    end

    if length(Enum.uniq(cols)) != length(cols) do
      raise CompileError,
        description:
          "unique index #{inspect(name)} lists a column more than once: " <>
            "#{inspect(cols, charlists: :as_lists)}"
    end

    Enum.each(cols, fn col ->
      unless MapSet.member?(declared, col) do
        raise CompileError,
          description:
            "unique index #{inspect(name)} references undeclared column #{inspect(col)}. " <>
              "Declare it with `column #{inspect(col)}, ...` " <>
              "(regex-matched columns are not supported in unique indexes)."
      end
    end)

    unless severity in [:error, :warning] do
      raise CompileError,
        description:
          "invalid severity #{inspect(severity)} for unique index #{inspect(name)}. " <>
            "Must be :error or :warning"
    end
  end
end
