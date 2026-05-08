defmodule Scrutinex.HeadersTest do
  use ExUnit.Case, async: true

  defmodule StrictSchema do
    use Scrutinex.Schema, strict: true

    column("id", :integer, required: true)
    column("name", :string, required: true)
  end

  defmodule OptionalSchema do
    use Scrutinex.Schema

    column("id", :integer, required: true)
    column("name", :string, required: false)
  end

  defmodule RegexRequiredSchema do
    use Scrutinex.Schema

    column("region", :string, required: true)
    column(~r/sales_.*/, :float, required: true)
  end

  defmodule RegexOptionalSchema do
    use Scrutinex.Schema

    column("region", :string, required: true)
    column(~r/sales_.*/, :float, required: false)
  end

  describe "validate_headers/2 — clean headers" do
    test "returns :ok when all required columns present and no extras in strict schema" do
      assert :ok = Scrutinex.validate_headers(["id", "name"], StrictSchema)
    end

    test "returns :ok when required columns present with optional absent in non-strict schema" do
      assert :ok = Scrutinex.validate_headers(["id"], OptionalSchema)
    end
  end

  describe "validate_headers/2 — duplicate headers" do
    test "returns error for duplicate column header" do
      assert {:error, errors} = Scrutinex.validate_headers(["id", "name", "id"], StrictSchema)

      dup = Enum.find(errors, &(&1.check == :duplicate_header))
      assert dup != nil
      assert dup.column == "id"
      assert dup.row == nil
      assert dup.metadata.count == 2
      assert dup.metadata.column == "id"
    end

    test "reports each distinct duplicate independently" do
      assert {:error, errors} =
               Scrutinex.validate_headers(["a", "b", "a", "b"], OptionalSchema)

      dup_checks = Enum.filter(errors, &(&1.check == :duplicate_header))
      dup_columns = Enum.map(dup_checks, & &1.column) |> Enum.sort()
      assert "a" in dup_columns
      assert "b" in dup_columns
    end
  end

  describe "validate_headers/2 — missing required string columns" do
    test "returns error with :required check when required string column is absent" do
      assert {:error, errors} = Scrutinex.validate_headers(["id"], StrictSchema)

      req = Enum.find(errors, &(&1.check == :required))
      assert req != nil
      assert req.column == "name"
      assert req.row == nil
    end

    test "empty header list triggers required errors for all required columns" do
      assert {:error, errors} = Scrutinex.validate_headers([], StrictSchema)

      required_errors = Enum.filter(errors, &(&1.check == :required))
      columns = Enum.map(required_errors, & &1.column) |> Enum.sort()
      assert "id" in columns
      assert "name" in columns
    end
  end

  describe "validate_headers/2 — required regex columns" do
    test "returns :required_columns error when required regex column has no matching header" do
      assert {:error, errors} =
               Scrutinex.validate_headers(["region"], RegexRequiredSchema)

      regex_err = Enum.find(errors, &(&1.check == :required_columns))
      assert regex_err != nil
      assert regex_err.row == nil
    end

    test "returns :ok when required regex column has at least one matching header" do
      assert :ok =
               Scrutinex.validate_headers(["region", "sales_q1"], RegexRequiredSchema)
    end

    test "optional regex column with no match does not produce required_columns error" do
      assert :ok = Scrutinex.validate_headers(["region"], RegexOptionalSchema)
    end
  end

  describe "validate_headers/2 — strict mode unknown columns" do
    test "returns :unexpected_column error for header not in schema" do
      assert {:error, errors} =
               Scrutinex.validate_headers(["id", "name", "extra"], StrictSchema)

      unknown = Enum.find(errors, &(&1.check == :unexpected_column))
      assert unknown != nil
      assert unknown.column == "extra"
      assert unknown.row == nil
      assert unknown.metadata.column == "extra"
    end

    test "non-strict schema does not report unexpected columns" do
      assert :ok = Scrutinex.validate_headers(["id", "name", "extra"], OptionalSchema)
    end
  end

  describe "validate_headers/2 — all errors have row: nil" do
    test "all returned errors have row: nil (schema-level errors)" do
      # duplicates + missing required + unexpected
      assert {:error, errors} =
               Scrutinex.validate_headers(["id", "id", "ghost"], StrictSchema)

      assert Enum.all?(errors, &(&1.row == nil))
    end
  end

  describe "validate_headers/2 — case sensitivity" do
    test "header matching is case-sensitive" do
      # "Id" != "id", so "id" is missing
      assert {:error, errors} = Scrutinex.validate_headers(["Id", "name"], StrictSchema)

      req = Enum.find(errors, &(&1.check == :required and &1.column == "id"))
      assert req != nil
    end
  end

  describe "validate_headers!/2" do
    test "returns :ok on success" do
      assert :ok = Scrutinex.validate_headers!(["id", "name"], StrictSchema)
    end

    test "raises ValidationError on failure" do
      assert_raise Scrutinex.ValidationError, ~r/header validation failed/, fn ->
        Scrutinex.validate_headers!(["id", "id"], StrictSchema)
      end
    end

    test "raised error contains errors list in result" do
      error =
        assert_raise Scrutinex.ValidationError, fn ->
          Scrutinex.validate_headers!([], StrictSchema)
        end

      assert error.result.errors != []
      assert Enum.all?(error.result.errors, &(&1.row == nil))
    end
  end

  describe "validate_headers/2 — argument validation" do
    test "raises ArgumentError when headers is not a list" do
      assert_raise ArgumentError, ~r/expected a list/, fn ->
        Scrutinex.validate_headers("not a list", StrictSchema)
      end
    end

    test "raises ArgumentError when schema_module is not an atom" do
      assert_raise ArgumentError, ~r/expected a schema module/, fn ->
        Scrutinex.validate_headers(["id"], "NotAModule")
      end
    end

    test "raises ArgumentError when schema_module does not implement __schema__/0" do
      assert_raise ArgumentError, ~r/__schema__\/0/, fn ->
        Scrutinex.validate_headers(["id"], String)
      end
    end
  end
end
