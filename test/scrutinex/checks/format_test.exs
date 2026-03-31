defmodule Scrutinex.Checks.FormatTest do
  use ExUnit.Case, async: true
  alias Scrutinex.Checks.Format

  describe "run/2" do
    test "passes when value matches regex" do
      assert :ok = Format.run("ABC-123", ~r/^[A-Z]+-\d+$/)
    end

    test "fails when value does not match regex" do
      assert {:error, "must match format %{format}", %{format: _}} =
               Format.run("abc", ~r/^[A-Z]+$/)
    end
  end
end
