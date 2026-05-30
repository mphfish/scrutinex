defmodule Scrutinex.Schema.Definition do
  @moduledoc "Schema definition struct holding columns, checks, indexes, and strict flag."
  @type t :: %__MODULE__{
          columns: [Scrutinex.Column.t()],
          checks: [Scrutinex.Check.t()],
          indexes: [Scrutinex.Index.t()],
          strict: boolean()
        }

  defstruct columns: [], checks: [], indexes: [], strict: false
end
