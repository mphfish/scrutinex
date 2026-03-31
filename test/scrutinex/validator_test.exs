defmodule Scrutinex.ValidatorTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Error

  defmodule BasicSchema do
    use Scrutinex.Schema

    column("name", :string, required: true, checks: [length: [min: 1]])
    column("age", :integer)
  end

  defmodule CoercionSchema do
    use Scrutinex.Schema

    column("id", :integer, coerce: true)
    column("amount", :float, coerce: true)
    column("active", :boolean, coerce: true)
  end

  defmodule NullableSchema do
    use Scrutinex.Schema

    column("required_field", :string)
    column("optional_field", :string, nullable: true)
  end

  defmodule ChecksSchema do
    use Scrutinex.Schema

    column("status", :string, checks: [inclusion: ["active", "inactive"]])

    column("score", :integer,
      checks: [number: [greater_than_or_equal_to: 0, less_than_or_equal_to: 100]]
    )
  end

  defmodule StrictSchema do
    use Scrutinex.Schema, strict: true

    column("name", :string)
  end

  defmodule RegexSchema do
    use Scrutinex.Schema

    column("id", :integer)
    column(~r/sales_.*/, :float, coerce: true, checks: [number: [greater_than_or_equal_to: 0]])
  end

  defmodule CrossColumnSchema do
    use Scrutinex.Schema

    column("start", :string)
    column("end", :string)

    check :ordering do
      fn row -> row["start"] < row["end"] end
    end

    check :not_same, message: "start and end must differ" do
      fn row -> row["start"] != row["end"] end
    end
  end

  describe "presence checks" do
    test "valid data passes" do
      data = [%{"name" => "Alice", "age" => 30}]
      result = Scrutinex.validate(data, BasicSchema)
      assert result.valid?
    end

    test "missing required column produces error" do
      data = [%{"age" => 30}]
      result = Scrutinex.validate(data, BasicSchema)
      refute result.valid?
      assert [%Error{row: 0, column: "name", check: :required}] = result.errors
    end
  end

  describe "strict mode" do
    test "rejects unexpected columns" do
      data = [%{"name" => "Alice", "extra" => "oops"}]
      result = Scrutinex.validate(data, StrictSchema)
      refute result.valid?
      assert [%Error{row: 0, column: "extra", check: :unexpected_column}] = result.errors
    end

    test "accepts data with only declared columns" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, StrictSchema)
      assert result.valid?
    end
  end

  describe "coercion" do
    test "coerces string values to declared types" do
      data = [%{"id" => "42", "amount" => "3.14", "active" => "true"}]
      result = Scrutinex.validate(data, CoercionSchema)
      assert result.valid?
      assert [%{"id" => 42, "amount" => 3.14, "active" => true}] = result.data
    end

    test "passes through already-correct types" do
      data = [%{"id" => 42, "amount" => 3.14, "active" => true}]
      result = Scrutinex.validate(data, CoercionSchema)
      assert result.valid?
      assert [%{"id" => 42, "amount" => 3.14, "active" => true}] = result.data
    end

    test "coercion failure produces error and skips further checks" do
      data = [%{"id" => "abc", "amount" => "3.14", "active" => "true"}]
      result = Scrutinex.validate(data, CoercionSchema)
      refute result.valid?
      assert [%Error{row: 0, column: "id", check: :coercion}] = result.errors
    end
  end

  defmodule NullableWithChecksSchema do
    use Scrutinex.Schema

    column("code", :string, nullable: false, checks: [length: [min: 1]])
    column("label", :string, nullable: true, checks: [length: [min: 1]])
  end

  describe "nullability" do
    test "nil in non-nullable column produces error" do
      data = [%{"required_field" => nil, "optional_field" => nil}]
      result = Scrutinex.validate(data, NullableSchema)
      refute result.valid?
      assert [%Error{row: 0, column: "required_field", check: :not_null}] = result.errors
    end

    test "empty string in non-nullable column produces error" do
      data = [%{"required_field" => "", "optional_field" => ""}]
      result = Scrutinex.validate(data, NullableSchema)
      refute result.valid?
      assert [%Error{row: 0, column: "required_field", check: :not_null}] = result.errors
    end

    test "nil in nullable column is allowed" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, NullableSchema)
      assert result.valid?
    end

    test "B1: empty string in non-nullable column with checks produces :not_null, not check error" do
      data = [%{"code" => "", "label" => "ok"}]
      result = Scrutinex.validate(data, NullableWithChecksSchema)
      refute result.valid?
      assert [%Error{row: 0, column: "code", check: :not_null}] = result.errors
    end

    test "B1: empty string in nullable column with checks skips checks" do
      data = [%{"code" => "valid", "label" => ""}]
      result = Scrutinex.validate(data, NullableWithChecksSchema)
      assert result.valid?
    end

    test "B1: nil in nullable column with checks skips checks" do
      data = [%{"code" => "valid", "label" => nil}]
      result = Scrutinex.validate(data, NullableWithChecksSchema)
      assert result.valid?
    end
  end

  describe "column checks" do
    test "passes when checks pass" do
      data = [%{"status" => "active", "score" => 50}]
      result = Scrutinex.validate(data, ChecksSchema)
      assert result.valid?
    end

    test "fails when check fails" do
      data = [%{"status" => "deleted", "score" => 150}]
      result = Scrutinex.validate(data, ChecksSchema)
      refute result.valid?
      assert length(result.errors) == 2
    end
  end

  describe "regex column matching" do
    test "applies rules to matching columns" do
      data = [%{"id" => 1, "sales_q1" => "10.0", "sales_q2" => "20.0"}]
      result = Scrutinex.validate(data, RegexSchema)
      assert result.valid?
      [row] = result.data
      assert row["sales_q1"] == 10.0
      assert row["sales_q2"] == 20.0
    end

    test "fails when regex-matched column violates check" do
      data = [%{"id" => 1, "sales_q1" => "-5.0"}]
      result = Scrutinex.validate(data, RegexSchema)
      refute result.valid?
      assert [%Error{column: "sales_q1", check: :number}] = result.errors
    end
  end

  describe "cross-column checks" do
    test "passes when cross-column check passes" do
      data = [%{"start" => "2024-01-01", "end" => "2024-12-31"}]
      result = Scrutinex.validate(data, CrossColumnSchema)
      assert result.valid?
    end

    test "fails when cross-column check fails" do
      data = [%{"start" => "2024-12-31", "end" => "2024-01-01"}]
      result = Scrutinex.validate(data, CrossColumnSchema)
      refute result.valid?
      assert [%Error{row: 0, column: nil, check: :ordering}] = result.errors
    end

    test "uses custom message" do
      data = [%{"start" => "same", "end" => "same"}]
      result = Scrutinex.validate(data, CrossColumnSchema)
      refute result.valid?

      errors = result.errors
      not_same_error = Enum.find(errors, &(&1.check == :not_same))
      assert not_same_error.message == "start and end must differ"
    end
  end

  describe "multiple rows" do
    test "validates all rows and collects all errors" do
      data = [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "", "age" => 25},
        %{"age" => 20}
      ]

      result = Scrutinex.validate(data, BasicSchema)
      refute result.valid?
      assert length(result.errors) == 2

      row1_error = Enum.find(result.errors, &(&1.row == 1))
      assert row1_error.check == :not_null

      row2_error = Enum.find(result.errors, &(&1.row == 2))
      assert row2_error.check == :required
    end
  end

  describe "type checking without coercion" do
    test "wrong type produces error" do
      data = [%{"name" => "Alice", "age" => "not_an_int"}]
      result = Scrutinex.validate(data, BasicSchema)
      refute result.valid?
      assert [%Error{column: "age", check: :type}] = result.errors
    end
  end
end
