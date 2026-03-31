defmodule Scrutinex.Checks.ExclusionTest do
  use ExUnit.Case, async: true
  alias Scrutinex.Checks.Exclusion

  describe "run/2" do
    test "passes when value is not in list" do
      assert :ok = Exclusion.run("active", ["banned", "blocked"])
    end

    test "fails when value is in list" do
      assert {:error, "must not be one of %{values}", %{values: "banned, blocked"}} =
               Exclusion.run("banned", ["banned", "blocked"])
    end
  end
end
