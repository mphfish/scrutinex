defmodule Scrutinex.Result do
  @moduledoc """
  Validation result, inspired by Ecto changesets.

  Contains the validated (and possibly coerced) data alongside any errors.
  `valid?` is `true` when there are no `:error`-severity errors (warnings alone
  do not cause `valid?` to be `false`).
  """

  alias Scrutinex.Error

  @type t :: %__MODULE__{
          valid?: boolean(),
          data: [map()],
          errors: [Error.t()]
        }

  defstruct valid?: true, data: [], errors: []

  @doc """
  Filters errors by column name or row index.

  ## Examples

      Scrutinex.Result.errors_for(result, "age")
      #=> [%Scrutinex.Error{column: "age", ...}]

      Scrutinex.Result.errors_for(result, row: 0)
      #=> [%Scrutinex.Error{row: 0, ...}]

      Scrutinex.Result.errors_for(result, check: :number)
      #=> [%Scrutinex.Error{check: :number, ...}]
  """
  @spec errors_for(
          t(),
          String.t()
          | [{:row, non_neg_integer()} | {:check, atom()} | {:severity, :error | :warning}]
        ) :: [Error.t()]
  def errors_for(result, filter)

  def errors_for(%__MODULE__{errors: errors}, column) when is_binary(column) do
    Enum.filter(errors, &(&1.column == column))
  end

  def errors_for(%__MODULE__{errors: errors}, row: row) when is_integer(row) do
    Enum.filter(errors, &(&1.row == row))
  end

  def errors_for(%__MODULE__{errors: errors}, check: check) when is_atom(check) do
    Enum.filter(errors, &(&1.check == check))
  end

  def errors_for(%__MODULE__{errors: errors}, severity: severity)
      when severity in [:error, :warning] do
    Enum.filter(errors, &(&1.severity == severity))
  end

  @doc """
  Returns only errors with severity `:warning`.

  ## Examples

      Scrutinex.Result.warnings(result)
      #=> [%Scrutinex.Error{severity: :warning, ...}]
  """
  @spec warnings(t()) :: [Error.t()]
  def warnings(%__MODULE__{errors: errors}) do
    Enum.filter(errors, &(&1.severity == :warning))
  end

  @doc """
  Returns only errors with severity `:error` (excludes warnings).

  ## Examples

      Scrutinex.Result.errors_only(result)
      #=> [%Scrutinex.Error{severity: :error, ...}]
  """
  @spec errors_only(t()) :: [Error.t()]
  def errors_only(%__MODULE__{errors: errors}) do
    Enum.filter(errors, &(&1.severity == :error))
  end

  @doc """
  Groups errors by column name with interpolated messages.

  Returns a map of column names to lists of formatted error messages.
  Cross-column errors (with `column: nil`) are grouped under `nil`.

  ## Examples

      Scrutinex.Result.errors_to_map(result)
      #=> %{"age" => ["must be greater than 0"], "name" => ["is required"]}
  """
  @spec errors_to_map(t()) :: %{optional(String.t() | nil) => [String.t()]}
  def errors_to_map(%__MODULE__{errors: errors}) do
    errors
    |> Enum.group_by(& &1.column)
    |> Map.new(fn {col, errs} ->
      {col, Enum.map(errs, &Scrutinex.Error.format_message/1)}
    end)
  end
end
