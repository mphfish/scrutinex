defmodule Scrutinex.Checks.NumberTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Checks.Number

  describe "run/2" do
    test "greater_than" do
      assert :ok = Number.run(5, greater_than: 0)
      assert {:error, _, _} = Number.run(0, greater_than: 0)
      assert {:error, _, _} = Number.run(-1, greater_than: 0)
    end

    test "greater_than_or_equal_to" do
      assert :ok = Number.run(0, greater_than_or_equal_to: 0)
      assert :ok = Number.run(1, greater_than_or_equal_to: 0)
      assert {:error, _, _} = Number.run(-1, greater_than_or_equal_to: 0)
    end

    test "less_than" do
      assert :ok = Number.run(0, less_than: 5)
      assert {:error, _, _} = Number.run(5, less_than: 5)
    end

    test "less_than_or_equal_to" do
      assert :ok = Number.run(5, less_than_or_equal_to: 5)
      assert :ok = Number.run(4, less_than_or_equal_to: 5)
      assert {:error, _, _} = Number.run(6, less_than_or_equal_to: 5)
    end

    test "equal_to" do
      assert :ok = Number.run(5, equal_to: 5)
      assert {:error, _, _} = Number.run(4, equal_to: 5)
    end

    test "not_equal_to" do
      assert :ok = Number.run(4, not_equal_to: 5)
      assert {:error, _, _} = Number.run(5, not_equal_to: 5)
    end

    test "multiple constraints" do
      assert :ok = Number.run(5, greater_than: 0, less_than: 10)
      assert {:error, _, _} = Number.run(0, greater_than: 0, less_than: 10)
      assert {:error, _, _} = Number.run(10, greater_than: 0, less_than: 10)
    end

    test "returns error with message template and metadata" do
      assert {:error, "must be greater than %{number}", %{kind: :greater_than, number: 0}} =
               Number.run(-1, greater_than: 0)
    end
  end
end
