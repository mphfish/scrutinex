defmodule Scrutinex.Checks.Number do
  @moduledoc """
  Numeric comparison checks (greater_than, less_than, equal_to, etc.).
  """

  @doc """
  Validates `value` against each comparison in `opts`.

  Supported keys: `:greater_than`, `:greater_than_or_equal_to`, `:less_than`,
  `:less_than_or_equal_to`, `:equal_to`, `:not_equal_to`.
  """
  @spec run(number(), keyword()) :: :ok | {:error, String.t(), map()}
  def run(value, opts) do
    Enum.reduce_while(opts, :ok, fn {kind, threshold}, :ok ->
      if compare(value, kind, threshold) do
        {:cont, :ok}
      else
        {:halt, {:error, message(kind), %{kind: kind, number: threshold}}}
      end
    end)
  end

  defp compare(value, :greater_than, n), do: value > n
  defp compare(value, :greater_than_or_equal_to, n), do: value >= n
  defp compare(value, :less_than, n), do: value < n
  defp compare(value, :less_than_or_equal_to, n), do: value <= n
  defp compare(value, :equal_to, n), do: value == n
  defp compare(value, :not_equal_to, n), do: value != n

  defp message(:greater_than), do: "must be greater than %{number}"
  defp message(:greater_than_or_equal_to), do: "must be greater than or equal to %{number}"
  defp message(:less_than), do: "must be less than %{number}"
  defp message(:less_than_or_equal_to), do: "must be less than or equal to %{number}"
  defp message(:equal_to), do: "must be equal to %{number}"
  defp message(:not_equal_to), do: "must not be equal to %{number}"
end
