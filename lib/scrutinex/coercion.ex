defmodule Scrutinex.Coercion do
  @moduledoc """
  Type coercion and type checking for column values.

  Coercion attempts to convert a value (typically a string from CSV/external
  data) into the target Elixir type. Type checking verifies that a value
  already matches the expected type without conversion.
  """

  @typedoc "Column types supported by coercion and type checking."
  @type supported_type :: :string | :integer | :float | :boolean | :date | :datetime

  @doc """
  Attempts to coerce `value` to the given `type`.

  Returns `{:ok, coerced_value}` on success or `{:error, message}` on failure.
  """
  @spec coerce(term(), supported_type()) :: {:ok, term()} | {:error, String.t()}
  def coerce(value, :string) when is_binary(value), do: {:ok, value}

  def coerce(value, :string),
    do: {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to string"}

  def coerce(value, :integer) when is_integer(value), do: {:ok, value}

  def coerce(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to integer"}
    end
  end

  def coerce(value, :integer),
    do: {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to integer"}

  def coerce(value, :float) when is_float(value), do: {:ok, value}
  def coerce(value, :float) when is_integer(value), do: {:ok, value}

  def coerce(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to float"}
    end
  end

  def coerce(value, :float),
    do: {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to float"}

  def coerce(value, :boolean) when is_boolean(value), do: {:ok, value}
  def coerce("true", :boolean), do: {:ok, true}
  def coerce("1", :boolean), do: {:ok, true}
  def coerce("false", :boolean), do: {:ok, false}
  def coerce("0", :boolean), do: {:ok, false}

  def coerce(value, :boolean),
    do: {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to boolean"}

  def coerce(%Date{} = value, :date), do: {:ok, value}

  def coerce(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, date}

      {:error, _} ->
        {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to date"}
    end
  end

  def coerce(value, :date),
    do: {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to date"}

  def coerce(%NaiveDateTime{} = value, :datetime), do: {:ok, value}
  def coerce(%DateTime{} = value, :datetime), do: {:ok, value}

  def coerce(value, :datetime) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, dt} ->
        {:ok, dt}

      {:error, _} ->
        {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to datetime"}
    end
  end

  def coerce(value, :datetime),
    do: {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to datetime"}

  def coerce(value, type) do
    {:error, "cannot cast #{inspect(value, limit: 5, printable_limit: 100)} to #{inspect(type)}"}
  end

  @doc """
  Checks whether `value` already matches the expected `type` without coercion.

  Returns `:ok` or `{:error, message}`.
  """
  @spec type_check(term(), supported_type()) :: :ok | {:error, String.t()}
  def type_check(value, :string) when is_binary(value), do: :ok
  def type_check(value, :integer) when is_integer(value), do: :ok
  def type_check(value, :float) when is_float(value) or is_integer(value), do: :ok
  def type_check(value, :boolean) when is_boolean(value), do: :ok
  def type_check(%Date{}, :date), do: :ok
  def type_check(%NaiveDateTime{}, :datetime), do: :ok
  def type_check(%DateTime{}, :datetime), do: :ok

  def type_check(value, type) do
    {:error, "expected #{type}, got #{inspect(value, limit: 5, printable_limit: 100)}"}
  end
end
