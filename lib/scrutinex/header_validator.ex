defmodule Scrutinex.HeaderValidator do
  @moduledoc false

  alias Scrutinex.{Column, Error}

  @doc false
  @spec validate(list(String.t()), Scrutinex.Schema.Definition.t()) :: :ok | {:error, [Error.t()]}
  def validate(headers, schema) do
    errors =
      check_duplicates(headers) ++
        check_required(headers, schema.columns) ++
        check_strict(headers, schema)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp check_duplicates(headers) do
    headers
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, count} ->
      %Error{
        row: nil,
        column: name,
        check: :duplicate_header,
        message: "duplicate column header",
        metadata: %{column: name, count: count}
      }
    end)
  end

  defp check_required(headers, columns) do
    Enum.flat_map(columns, fn
      %Column{name: name, required: true} when is_binary(name) ->
        if name in headers do
          []
        else
          [
            %Error{
              row: nil,
              column: name,
              check: :required,
              message: "column is required",
              metadata: %{column: name}
            }
          ]
        end

      %Column{name: %Regex{} = pattern, required: true} ->
        if Enum.any?(headers, &Regex.match?(pattern, &1)) do
          []
        else
          source = Regex.source(pattern)

          [
            %Error{
              row: nil,
              column: source,
              check: :required_columns,
              message: "no column matching %{pattern} found",
              metadata: %{pattern: source}
            }
          ]
        end

      _column ->
        []
    end)
  end

  defp check_strict(_headers, %{strict: false}), do: []

  defp check_strict(headers, %{strict: true, columns: columns}) do
    headers
    |> Enum.reject(&column_declared?(&1, columns))
    |> Enum.map(fn name ->
      %Error{
        row: nil,
        column: name,
        check: :unexpected_column,
        message: "unexpected column",
        metadata: %{column: name}
      }
    end)
  end

  defp column_declared?(header, columns) do
    Enum.any?(columns, fn
      %Column{name: name} when is_binary(name) -> name == header
      %Column{name: %Regex{} = pattern} -> Regex.match?(pattern, header)
    end)
  end
end
