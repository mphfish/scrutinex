defmodule Scrutinex.Checks.Custom do
  @moduledoc """
  Runs a user-supplied function as a column-level check.
  """

  @doc """
  Calls `func.(value)` and returns `:ok` if truthy, otherwise a generic error.

  Accepts either a plain function or a `{function, message}` tuple. When a
  tuple is given, the custom `message` is used in the error instead of the
  default "custom check failed" text.

  If the function raises, the exception is caught and returned as a validation
  error rather than crashing the pipeline.
  """
  @spec run(term(), (term() -> boolean()) | {(term() -> boolean()), String.t()}) ::
          :ok | {:error, String.t(), map()}
  def run(value, {func, message}) when is_function(func, 1) do
    safe_run(value, func, message)
  end

  def run(value, func) when is_function(func, 1) do
    safe_run(value, func, "custom check failed")
  end

  defp safe_run(value, func, message) do
    if func.(value) do
      :ok
    else
      {:error, message, %{}}
    end
  rescue
    e ->
      {:error, "custom check raised: #{Exception.message(e)}", %{kind: :exception}}
  end
end
