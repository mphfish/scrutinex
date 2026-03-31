defmodule Scrutinex.ValidationError do
  @moduledoc "Raised by `Scrutinex.validate!/2` when validation fails."
  defexception [:message, :result]

  @impl true
  def message(%{message: msg}), do: msg
end
