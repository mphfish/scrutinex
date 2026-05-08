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
    * `:nullable` - allow `nil` / empty values (default `false`)
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
        column ~r/^score_/, :float, required: false, nullable: true

        check :age_name_consistency do
          fn row -> !(row["age"] > 150 && row["name"] == "") end
        end
      end

      result = Scrutinex.validate(data, MyApp.PeopleSchema)
  """

  alias Scrutinex.{Column, Check}

  defmacro __using__(opts) do
    quote do
      Module.register_attribute(__MODULE__, :scrutinex_columns, accumulate: true)
      Module.register_attribute(__MODULE__, :scrutinex_checks, accumulate: true)
      Module.put_attribute(__MODULE__, :scrutinex_strict, unquote(opts[:strict] || false))

      import Scrutinex.Schema, only: [column: 2, column: 3, check: 2, check: 3]

      @before_compile Scrutinex.Schema
    end
  end

  defmacro column(name, type, opts \\ []) do
    raw_checks = Keyword.get(opts, :checks, [])
    column_severity = Keyword.get(opts, :severity, :error)

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
        required: unquote(Keyword.get(opts, :required, true)),
        coerce: unquote(Keyword.get(opts, :coerce, false)),
        nullable: unquote(Keyword.get(opts, :nullable, false)),
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

  @valid_types [:string, :integer, :float, :boolean, :date, :datetime]
  @valid_checks [:number, :inclusion, :exclusion, :format, :length, :custom]

  defmacro __before_compile__(env) do
    columns = Module.get_attribute(env.module, :scrutinex_columns) |> Enum.reverse()
    checks_raw = Module.get_attribute(env.module, :scrutinex_checks) |> Enum.reverse()
    strict = Module.get_attribute(env.module, :scrutinex_strict)

    for %Column{type: type, name: name, checks: checks} <- columns do
      unless type in @valid_types do
        raise CompileError,
          description:
            "invalid column type #{inspect(type)} for column #{inspect(name)}. " <>
              "Must be one of: #{inspect(@valid_types)}"
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

    quote do
      @doc "Returns the schema definition for this module."
      @spec __schema__() :: Scrutinex.Schema.Definition.t()
      def __schema__ do
        %Scrutinex.Schema.Definition{
          columns: unquote(escaped_columns),
          checks: unquote(checks),
          strict: unquote(strict)
        }
      end
    end
  end
end
