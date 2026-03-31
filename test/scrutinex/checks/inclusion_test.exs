defmodule Scrutinex.Checks.InclusionTest do
  use ExUnit.Case, async: true
  alias Scrutinex.Checks.Inclusion

  describe "run/2" do
    test "passes when value is in list" do
      assert :ok = Inclusion.run("active", ["active", "inactive"])
    end

    test "fails when value is not in list" do
      assert {:error, "must be one of %{values}", %{values: "active, inactive"}} =
               Inclusion.run("unknown", ["active", "inactive"])
    end
  end
end
