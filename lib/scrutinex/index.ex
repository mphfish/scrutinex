defmodule Scrutinex.Index do
  @moduledoc """
  Represents a unique index — a declaration that the tuple of values across
  one or more columns must not repeat across rows.

  Defined via the `unique` macro in `Scrutinex.Schema`. Evaluated as a
  cross-row pass after coercion. The first row with a given tuple is canonical;
  every later row with the same tuple produces an `Error` whose `check:` is the
  index `:name` (default `:unique`) and whose `column:` is `nil`.

  Rows where any indexed column is missing, `nil`, or `""` are excluded from
  the check (SQL-null semantics). Rows are also excluded when an indexed
  column's value failed to coerce or type-check to its declared type, since
  such a cell has no valid coerced value to compare.

  ## Fields

    * `:name` - atom identifying the index; becomes the error `check:` field
      (default `:unique`)
    * `:columns` - non-empty list of declared column names (string literals, not
      regex patterns); columns may be of any type
    * `:message` - error message template, default `"is a duplicate of row %{first_row}"`
    * `:severity` - `:error` (default) or `:warning`
  """

  @type t :: %__MODULE__{
          name: atom(),
          columns: [String.t()],
          message: String.t(),
          severity: :error | :warning
        }

  @enforce_keys [:name, :columns]
  defstruct [:name, :columns, message: "is a duplicate of row %{first_row}", severity: :error]
end
