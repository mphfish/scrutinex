defmodule Scrutinex.Checks.Length do
  @moduledoc """
  Validates string length against `:min`, `:max`, and/or `:is` constraints.
  """

  @doc """
  Checks that `String.length(value)` satisfies each constraint in `opts`.
  """
  @spec run(String.t(), keyword()) :: :ok | {:error, String.t(), map()}
  def run(value, opts) do
    # byte_size/1 is O(1). For ASCII strings, byte_size == String.length.
    # Use it as a fast path to avoid the expensive O(n) grapheme count.
    byte_len = byte_size(value)

    case fast_check(byte_len, opts) do
      :ok -> :ok
      :needs_grapheme_count -> slow_check(String.length(value), opts)
      {:error, _, _} = err -> err
    end
  end

  # Fast path using byte_size (O(1)):
  # - byte_size >= grapheme_length always, so:
  #   - byte_size < min  => definitely fails min
  #   - byte_size <= max => definitely passes max (graphemes <= bytes)
  #   - byte_size == is  => might pass is (only if ASCII)
  defp fast_check(byte_len, opts) do
    Enum.reduce_while(opts, :ok, fn
      {:min, count}, :ok when byte_len < count ->
        {:halt, {:error, message(:min), %{kind: :min, count: count}}}

      {:max, count}, :ok when byte_len <= count ->
        {:cont, :ok}

      {:is, count}, :ok when byte_len < count ->
        {:halt, {:error, message(:is), %{kind: :is, count: count}}}

      _constraint, :ok ->
        {:halt, :needs_grapheme_count}
    end)
  end

  defp slow_check(len, opts) do
    Enum.reduce_while(opts, :ok, fn {kind, count}, :ok ->
      if length_check(len, kind, count) do
        {:cont, :ok}
      else
        {:halt, {:error, message(kind), %{kind: kind, count: count}}}
      end
    end)
  end

  defp length_check(len, :min, count), do: len >= count
  defp length_check(len, :max, count), do: len <= count
  defp length_check(len, :is, count), do: len == count

  defp message(:min), do: "must have length at least %{count}"
  defp message(:max), do: "must have length at most %{count}"
  defp message(:is), do: "must have length exactly %{count}"
end
