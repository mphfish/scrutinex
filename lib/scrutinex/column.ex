defmodule Scrutinex.Column do
  @moduledoc """
  Defines a single column in a Scrutinex schema.

  ## Fields

    * `:name` - column key as a string, or a `Regex` to match multiple columns
    * `:type` - expected data type (`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`)
    * `:required` - when `true` (default), the column must be present in every row
    * `:coerce` - when `true`, attempts to cast the value to `:type` before validation
    * `:on_empty` - controls behaviour when a cell value is `nil` or `""`:
      - `:error` (default) — produces a severity `:error` and skips remaining checks
      - `:warn` — produces a severity `:warning` and skips remaining checks
      - `:ignore` — produces no error and skips remaining checks
    * `:checks` - keyword list of check tuples, e.g. `[number: [greater_than: 0]]`
  """

  @type t :: %__MODULE__{
          name: String.t() | Regex.t(),
          type: :string | :integer | :float | :boolean | :date | :datetime,
          required: boolean(),
          coerce: boolean(),
          on_empty: :error | :warn | :ignore,
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
    on_empty: :error,
    checks: [],
    severity: :error,
    check_severities: %{}
  ]
end
