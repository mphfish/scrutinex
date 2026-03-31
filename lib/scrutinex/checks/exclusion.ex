defmodule Scrutinex.Checks.Exclusion do
  @moduledoc """
  Validates that a value is not a member of a forbidden list.
  """

  @doc """
  Returns `:ok` if `value` is not in `list`, otherwise an error.
  """
  @spec run(term(), list()) :: :ok | {:error, String.t(), map()}
  def run(value, list) do
    if value in list do
      {:error, "must not be one of %{values}", %{values: Enum.join(list, ", ")}}
    else
      :ok
    end
  end
end
