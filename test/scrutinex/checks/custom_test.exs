defmodule Scrutinex.Checks.CustomTest do
  use ExUnit.Case, async: true
  alias Scrutinex.Checks.Custom

  describe "run/2" do
    test "passes when function returns true" do
      assert :ok = Custom.run(42, &(&1 > 0))
    end

    test "fails when function returns false" do
      assert {:error, "custom check failed", %{}} = Custom.run(-1, &(&1 > 0))
    end

    test "accepts {function, message} tuple for custom error messages" do
      assert :ok = Custom.run(18, {&(&1 >= 18), "must be 18 or older"})

      assert {:error, "must be 18 or older", %{}} =
               Custom.run(15, {&(&1 >= 18), "must be 18 or older"})
    end
  end
end
