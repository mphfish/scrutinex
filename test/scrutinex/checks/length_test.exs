defmodule Scrutinex.Checks.LengthTest do
  use ExUnit.Case, async: true
  alias Scrutinex.Checks.Length

  describe "run/2" do
    test "min length passes" do
      assert :ok = Length.run("abc", min: 2)
    end

    test "min length fails" do
      assert {:error, "must have length at least %{count}", %{kind: :min, count: 3}} =
               Length.run("ab", min: 3)
    end

    test "max length passes" do
      assert :ok = Length.run("ab", max: 5)
    end

    test "max length fails" do
      assert {:error, "must have length at most %{count}", %{kind: :max, count: 2}} =
               Length.run("abc", max: 2)
    end

    test "exact length with :is" do
      assert :ok = Length.run("abc", is: 3)

      assert {:error, "must have length exactly %{count}", %{kind: :is, count: 3}} =
               Length.run("ab", is: 3)
    end

    test "combined min and max" do
      assert :ok = Length.run("abc", min: 1, max: 5)
      assert {:error, _, _} = Length.run("", min: 1, max: 5)
    end
  end
end
