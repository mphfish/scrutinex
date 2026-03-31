defmodule Scrutinex.Checks.Format do
  @moduledoc """
  Validates that a string value matches a regular expression.
  """

  @doc """
  Returns `:ok` if `value` matches `regex`, otherwise an error.
  """
  @spec run(String.t(), Regex.t()) :: :ok | {:error, String.t(), map()}
  def run(value, %Regex{re_pattern: pattern} = regex) do
    case :re.run(value, pattern, [:global, {:capture, :none}, {:match_limit, 10_000}]) do
      :match -> :ok
      _ -> {:error, "must match format %{format}", %{format: Regex.source(regex)}}
    end
  end
end
