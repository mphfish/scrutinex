defmodule Scrutinex.Error do
  @moduledoc """
  Represents a single validation failure.

  ## Fields

    * `:row` - zero-based row index where the error occurred
    * `:column` - column name as a string, or `nil` for cross-column checks
    * `:check` - atom identifying the check that failed (e.g. `:required`, `:type`, `:number`)
    * `:message` - human-readable message using `%{key}` interpolation placeholders
      (Ecto-style) so callers can substitute metadata values for i18n
    * `:metadata` - map of substitution values for the message (e.g. `%{number: 10}`)
    * `:value` - the original value that failed validation, or `nil`
  """

  @type t :: %__MODULE__{
          row: non_neg_integer() | nil,
          column: String.t() | nil,
          check: atom(),
          message: String.t(),
          metadata: map(),
          value: term(),
          severity: :error | :warning
        }

  @enforce_keys [:row, :check, :message]
  defstruct [:row, :column, :check, :message, :value, metadata: %{}, severity: :error]

  @doc """
  Interpolates metadata values into the message template.

  ## Examples

      error = %Scrutinex.Error{message: "must be greater than %{number}", metadata: %{number: 0}, row: 0, check: :number}
      Scrutinex.Error.format_message(error)
      #=> "must be greater than 0"
  """
  @spec format_message(t()) :: String.t()
  def format_message(%__MODULE__{message: message, metadata: metadata}) do
    Enum.reduce(metadata, message, fn {key, val}, msg ->
      String.replace(msg, "%{#{key}}", to_string(val))
    end)
  end
end
