defmodule Scrutinex.Column do
  @moduledoc """
  Defines a single column in a Scrutinex schema.

  ## Fields

    * `:name` - column key as a string, or a `Regex` to match multiple columns
    * `:type` - expected data type (`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`)
    * `:required` - when `true` (default), the column must be present in every row
    * `:coerce` - when `true`, attempts to cast the value to `:type` before validation
    * `:nullable` - when `true`, allows `nil` and empty-string values
    * `:checks` - keyword list of check tuples, e.g. `[number: [greater_than: 0]]`
  """

  @type t :: %__MODULE__{
          name: String.t() | Regex.t(),
          type: :string | :integer | :float | :boolean | :date | :datetime,
          required: boolean(),
          coerce: boolean(),
          nullable: boolean(),
          checks: keyword(),
          severity: :error | :warning,
          check_severities: map()
        }

  @enforce_keys [:name, :type]
  defstruct [
    :name,
    :type,
    required: true,
    coerce: false,
    nullable: false,
    checks: [],
    severity: :error,
    check_severities: %{}
  ]
end
