defmodule Scrutinex.Checks.Inclusion do
  @moduledoc """
  Validates that a value is a member of an allowed list.
  """

  @doc """
  Returns `:ok` if `value` is in `list`, otherwise an error.
  """
  @spec run(term(), list()) :: :ok | {:error, String.t(), map()}
  def run(value, list) do
    if value in list do
      :ok
    else
      {:error, "must be one of %{values}", %{values: Enum.join(list, ", ")}}
    end
  end
end
