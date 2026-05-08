defmodule Scrutinex.Check do
  @moduledoc """
  Represents a cross-column (row-level) check defined via the `check` macro.

  The `:function` receives the entire row map and must return a truthy value
  for the check to pass. When it fails, an `Error` is produced with `column: nil`.
  """

  @type t :: %__MODULE__{
          name: atom(),
          message: String.t(),
          function: (map() -> boolean()),
          severity: :error | :warning
        }

  @enforce_keys [:name, :function]
  defstruct [:name, :function, message: "check failed", severity: :error]
end
