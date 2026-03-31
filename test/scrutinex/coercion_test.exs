defmodule Scrutinex.CoercionTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Coercion

  describe "coerce/2 with :integer" do
    test "passes through integers" do
      assert {:ok, 42} = Coercion.coerce(42, :integer)
    end

    test "casts string to integer" do
      assert {:ok, 42} = Coercion.coerce("42", :integer)
    end

    test "errors on non-numeric string" do
      assert {:error, "cannot cast \"abc\" to integer"} = Coercion.coerce("abc", :integer)
    end

    test "errors on wrong non-string type" do
      assert {:error, "cannot cast 42.5 to integer"} = Coercion.coerce(42.5, :integer)
    end
  end

  describe "coerce/2 with :float" do
    test "passes through floats" do
      assert {:ok, 3.14} = Coercion.coerce(3.14, :float)
    end

    test "passes through integers as floats" do
      assert {:ok, 42} = Coercion.coerce(42, :float)
    end

    test "casts string to float" do
      assert {:ok, 3.14} = Coercion.coerce("3.14", :float)
    end

    test "casts integer string to float" do
      assert {:ok, 42.0} = Coercion.coerce("42", :float)
    end

    test "errors on non-numeric string" do
      assert {:error, "cannot cast \"abc\" to float"} = Coercion.coerce("abc", :float)
    end
  end

  describe "coerce/2 with :string" do
    test "passes through strings" do
      assert {:ok, "hello"} = Coercion.coerce("hello", :string)
    end

    test "errors on non-string" do
      assert {:error, "cannot cast 42 to string"} = Coercion.coerce(42, :string)
    end
  end

  describe "coerce/2 with :boolean" do
    test "passes through booleans" do
      assert {:ok, true} = Coercion.coerce(true, :boolean)
      assert {:ok, false} = Coercion.coerce(false, :boolean)
    end

    test "casts truthy strings" do
      assert {:ok, true} = Coercion.coerce("true", :boolean)
      assert {:ok, true} = Coercion.coerce("1", :boolean)
    end

    test "casts falsy strings" do
      assert {:ok, false} = Coercion.coerce("false", :boolean)
      assert {:ok, false} = Coercion.coerce("0", :boolean)
    end

    test "errors on unknown string" do
      assert {:error, "cannot cast \"yes\" to boolean"} = Coercion.coerce("yes", :boolean)
    end
  end

  describe "coerce/2 with :date" do
    test "passes through Date structs" do
      date = ~D[2024-01-15]
      assert {:ok, ^date} = Coercion.coerce(date, :date)
    end

    test "casts ISO8601 string to Date" do
      assert {:ok, ~D[2024-01-15]} = Coercion.coerce("2024-01-15", :date)
    end

    test "errors on invalid date string" do
      assert {:error, "cannot cast \"not-a-date\" to date"} = Coercion.coerce("not-a-date", :date)
    end
  end

  describe "coerce/2 with :datetime" do
    test "passes through NaiveDateTime structs" do
      dt = ~N[2024-01-15 10:30:00]
      assert {:ok, ^dt} = Coercion.coerce(dt, :datetime)
    end

    test "passes through DateTime structs" do
      {:ok, dt, _} = DateTime.from_iso8601("2024-01-15T10:30:00Z")
      assert {:ok, ^dt} = Coercion.coerce(dt, :datetime)
    end

    test "casts ISO8601 string to NaiveDateTime" do
      assert {:ok, ~N[2024-01-15 10:30:00]} = Coercion.coerce("2024-01-15 10:30:00", :datetime)
    end

    test "errors on invalid datetime string" do
      assert {:error, "cannot cast \"nope\" to datetime"} = Coercion.coerce("nope", :datetime)
    end
  end

  describe "type_check/2 (no coercion)" do
    test "accepts correct types" do
      assert :ok = Coercion.type_check(42, :integer)
      assert :ok = Coercion.type_check(3.14, :float)
      assert :ok = Coercion.type_check(42, :float)
      assert :ok = Coercion.type_check("hi", :string)
      assert :ok = Coercion.type_check(true, :boolean)
      assert :ok = Coercion.type_check(~D[2024-01-01], :date)
      assert :ok = Coercion.type_check(~N[2024-01-01 00:00:00], :datetime)
    end

    test "rejects wrong types" do
      assert {:error, _} = Coercion.type_check("42", :integer)
      assert {:error, _} = Coercion.type_check(42, :string)
      assert {:error, _} = Coercion.type_check("true", :boolean)
    end
  end
end
