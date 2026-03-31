defmodule Scrutinex.Schema.Definition do
  @moduledoc "Schema definition struct holding columns, checks, and strict flag."
  @type t :: %__MODULE__{
          columns: [Scrutinex.Column.t()],
          checks: [Scrutinex.Check.t()],
          strict: boolean()
        }

  defstruct columns: [], checks: [], strict: false
end
