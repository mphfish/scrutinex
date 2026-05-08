defmodule Scrutinex do
  @moduledoc """
  Validates tabular data (lists of maps) against a schema definition.

  Define a schema using `Scrutinex.Schema`, then validate data with
  `validate/2` or `validate!/2`.

  ## Quick Start

      defmodule MySchema do
        use Scrutinex.Schema

        column "name",  :string,  checks: [length: [min: 1, max: 100]]
        column "age",   :integer, coerce: true, checks: [number: [greater_than: 0]]
        column "email", :string,  checks: [format: ~r/@/]
      end

      result = Scrutinex.validate(data, MySchema)

      if result.valid? do
        process(result.data)
      else
        handle_errors(result.errors)
      end

  See `Scrutinex.Schema` for the full DSL reference, supported types, and
  check options.
  """

  alias Scrutinex.{Result, Validator}

  @doc """
  Validates a list of row maps against the given schema module.

  Returns a `Scrutinex.Result` struct with `:valid?`, `:data` (with coerced
  values where applicable), and `:errors`.

  ## Options

    * `:max_errors` - stop validation after accumulating this many errors.
      Useful for quick validity checks or limiting output on large datasets.

  ## Examples

      result = Scrutinex.validate(data, MyApp.UserSchema)
      result.valid?   # => true or false
      result.errors   # => [%Scrutinex.Error{}, ...]

      # Stop after 10 errors
      result = Scrutinex.validate(data, MyApp.UserSchema, max_errors: 10)
  """
  @spec validate(list(map()), module(), keyword()) :: Result.t()
  def validate(data, schema_module, opts \\ []) do
    if not is_list(data) do
      raise ArgumentError,
            "expected a list of maps as first argument, got: " <>
              inspect(data, limit: 5, printable_limit: 100)
    end

    if not is_atom(schema_module) do
      raise ArgumentError,
            "expected a schema module as second argument, got: #{inspect(schema_module)}"
    end

    if data != [] and not is_map(hd(data)) do
      raise ArgumentError,
            "expected a list of maps, got a list starting with: #{inspect(hd(data))}"
    end

    if not function_exported?(schema_module, :__schema__, 0) do
      raise ArgumentError,
            "#{inspect(schema_module)} does not implement Scrutinex.Schema " <>
              "(missing __schema__/0 function)"
    end

    schema = schema_module.__schema__()
    Validator.validate(data, schema, opts)
  end

  @doc """
  Like `validate/2`, but raises `Scrutinex.ValidationError` on failure.

  On success, returns the list of coerced row maps directly (not wrapped in a
  `Result` struct). On failure, the raised `ValidationError` contains the full
  `Result` in its `:result` field.

  ## Examples

      # Success: returns coerced data
      rows = Scrutinex.validate!(data, MyApp.UserSchema)
      #=> [%{"name" => "Alice", "age" => 30}, ...]

      # Failure: raises with result attached
      try do
        Scrutinex.validate!(bad_data, MyApp.UserSchema)
      rescue
        e in Scrutinex.ValidationError ->
          e.result.errors  #=> [%Scrutinex.Error{}, ...]
      end
  """
  @spec validate!(list(map()), module(), keyword()) :: list(map())
  def validate!(data, schema_module, opts \\ []) do
    result = validate(data, schema_module, opts)

    if result.valid? do
      result.data
    else
      error_count = Enum.count(result.errors, &(&1.severity == :error))

      raise Scrutinex.ValidationError,
        message: "validation failed with #{error_count} error(s)",
        result: result
    end
  end
end
