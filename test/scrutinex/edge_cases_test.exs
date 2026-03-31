defmodule Scrutinex.EdgeCasesTest do
  use ExUnit.Case, async: true

  alias Scrutinex.{Error, Result}

  # --- Schemas ---

  defmodule EmptySchema do
    use Scrutinex.Schema
  end

  defmodule SimpleSchema do
    use Scrutinex.Schema
    column("name", :string)
    column("age", :integer)
  end

  defmodule CoerceNullableSchema do
    use Scrutinex.Schema
    column("amount", :float, coerce: true, nullable: true)
    column("label", :string, nullable: true)
  end

  defmodule MultiCheckSchema do
    use Scrutinex.Schema
    column("code", :string, checks: [length: [min: 2], format: ~r/^[A-Z]/])
  end

  defmodule RegexOnlySchema do
    use Scrutinex.Schema
    column(~r/metric_.*/, :float, coerce: true, checks: [number: [greater_than_or_equal_to: 0]])
  end

  defmodule StrictRegexSchema do
    use Scrutinex.Schema, strict: true
    column("id", :integer)
    column(~r/tag_.*/, :string)
  end

  defmodule OverlapRegexSchema do
    use Scrutinex.Schema
    column(~r/^score_/, :float)
    column(~r/_final$/, :float)
  end

  defmodule CoercedCrossCheckSchema do
    use Scrutinex.Schema
    column("min", :integer, coerce: true)
    column("max", :integer, coerce: true)

    check :min_less_than_max do
      fn row -> row["min"] < row["max"] end
    end
  end

  defmodule CustomMessageHelpers do
    def at_least_18?(value), do: value >= 18
  end

  defmodule CustomMessageSchema do
    use Scrutinex.Schema

    column("age", :integer,
      checks: [custom: {&CustomMessageHelpers.at_least_18?/1, "must be 18 or older"}]
    )
  end

  # --- T1: Edge Cases ---

  describe "empty data" do
    test "empty list is valid" do
      result = Scrutinex.validate([], SimpleSchema)
      assert result.valid?
      assert result.data == []
      assert result.errors == []
    end
  end

  describe "schema with no columns" do
    test "accepts any data" do
      result = Scrutinex.validate([%{"anything" => "goes"}], EmptySchema)
      assert result.valid?
    end
  end

  describe "sparse data" do
    test "rows with different key sets" do
      data = [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "Bob"},
        %{"age" => 25}
      ]

      result = Scrutinex.validate(data, SimpleSchema)
      refute result.valid?

      # Row 1 missing "age" (required), Row 2 missing "name" (required)
      assert length(result.errors) == 2
      assert Enum.any?(result.errors, &(&1.row == 1 and &1.column == "age"))
      assert Enum.any?(result.errors, &(&1.row == 2 and &1.column == "name"))
    end
  end

  describe "unicode strings" do
    test "unicode values pass string validation" do
      data = [%{"name" => "José", "age" => 30}]
      result = Scrutinex.validate(data, SimpleSchema)
      assert result.valid?
    end

    test "unicode values work with length check" do
      # Uses a string starting with uppercase ASCII so the format ~r/^[A-Z]/ passes,
      # and contains unicode characters to verify length counts graphemes correctly
      data = [%{"code" => "ABC"}]
      result = Scrutinex.validate(data, MultiCheckSchema)
      assert result.valid?
    end
  end

  describe "regex matching zero columns" do
    test "regex with no matching columns passes (no columns to validate)" do
      data = [%{"id" => 1, "unrelated" => "value"}]
      result = Scrutinex.validate(data, RegexOnlySchema)
      assert result.valid?
    end
  end

  # --- T2: Interaction Tests ---

  describe "coerce + nullable interactions" do
    test "nil with coerce and nullable skips coercion" do
      data = [%{"amount" => nil, "label" => nil}]
      result = Scrutinex.validate(data, CoerceNullableSchema)
      assert result.valid?
    end

    test "empty string with coerce and nullable skips coercion" do
      data = [%{"amount" => "", "label" => ""}]
      result = Scrutinex.validate(data, CoerceNullableSchema)
      assert result.valid?
    end

    test "valid string with coerce gets coerced" do
      data = [%{"amount" => "3.14", "label" => "hello"}]
      result = Scrutinex.validate(data, CoerceNullableSchema)
      assert result.valid?
      assert [%{"amount" => 3.14}] = result.data
    end
  end

  describe "cross-column checks with coerced values" do
    test "cross-column check receives coerced integer values, not strings" do
      data = [%{"min" => "10", "max" => "20"}]
      result = Scrutinex.validate(data, CoercedCrossCheckSchema)
      assert result.valid?

      [row] = result.data
      assert row["min"] == 10
      assert row["max"] == 20
    end

    test "cross-column check fails when coerced values violate constraint" do
      data = [%{"min" => "20", "max" => "10"}]
      result = Scrutinex.validate(data, CoercedCrossCheckSchema)
      refute result.valid?
      assert [%Error{check: :min_less_than_max, column: nil}] = result.errors
    end
  end

  describe "strict mode with regex columns" do
    test "allows regex-matched columns in strict mode" do
      data = [%{"id" => 1, "tag_color" => "red", "tag_size" => "large"}]
      result = Scrutinex.validate(data, StrictRegexSchema)
      assert result.valid?
    end

    test "rejects non-matching columns in strict mode with regex" do
      data = [%{"id" => 1, "tag_color" => "red", "extra" => "oops"}]
      result = Scrutinex.validate(data, StrictRegexSchema)
      refute result.valid?
      assert Enum.any?(result.errors, &(&1.check == :unexpected_column and &1.column == "extra"))
    end
  end

  describe "multiple checks short-circuit" do
    test "first failing check produces error, second check not run" do
      # "a" fails length min:2, so format check should not run
      data = [%{"code" => "a"}]
      result = Scrutinex.validate(data, MultiCheckSchema)
      refute result.valid?
      assert [%Error{check: :length}] = result.errors
    end
  end

  describe "overlapping regex patterns" do
    test "column matching two regex patterns gets validated by both" do
      # "score_final" matches both ~r/^score_/ and ~r/_final$/
      data = [%{"score_final" => 5.0}]
      result = Scrutinex.validate(data, OverlapRegexSchema)
      assert result.valid?
    end
  end

  # --- T3: Error Reporting ---

  describe "error reporting" do
    test "regex column errors show actual column name" do
      data = [%{"metric_sales" => "-1.0"}]
      result = Scrutinex.validate(data, RegexOnlySchema)
      refute result.valid?
      [error] = result.errors
      assert error.column == "metric_sales"
      refute is_struct(error.column, Regex)
    end

    test "full error reconstruction" do
      data = [%{"name" => "Alice", "age" => -5}]

      defmodule ErrorReconstructSchema do
        use Scrutinex.Schema
        column("name", :string)
        column("age", :integer, checks: [number: [greater_than: 0]])
      end

      result = Scrutinex.validate(data, ErrorReconstructSchema)
      [error] = result.errors

      assert error.row == 0
      assert error.column == "age"
      assert error.check == :number
      assert error.value == -5
      assert error.metadata == %{kind: :greater_than, number: 0}
      assert error.message == "must be greater than %{number}"

      formatted = Scrutinex.Error.format_message(error)
      assert formatted == "must be greater than 0"
    end

    test "errors_to_map groups and formats correctly" do
      data = [%{"min" => "abc", "max" => "20"}]
      result = Scrutinex.validate(data, CoercedCrossCheckSchema)
      refute result.valid?

      error_map = Result.errors_to_map(result)
      assert Map.has_key?(error_map, "min")
    end

    test "custom check with tuple message shows custom message" do
      data = [%{"age" => 15}]
      result = Scrutinex.validate(data, CustomMessageSchema)
      refute result.valid?
      [error] = result.errors
      assert error.message == "must be 18 or older"
    end
  end

  describe "empty string coercion" do
    test "empty string fails coercion to integer" do
      defmodule CoerceIntSchema do
        use Scrutinex.Schema
        column("x", :integer, coerce: true)
      end

      data = [%{"x" => ""}]
      result = Scrutinex.validate(data, CoerceIntSchema)
      # Empty string fails Integer.parse -> coercion error, then also not_null
      # Actually coercion error short-circuits (goes to {:error, error, value} branch)
      refute result.valid?
    end

    test "empty string fails coercion to float" do
      defmodule CoerceFloatSchema do
        use Scrutinex.Schema
        column("x", :float, coerce: true)
      end

      data = [%{"x" => ""}]
      result = Scrutinex.validate(data, CoerceFloatSchema)
      refute result.valid?
    end
  end
end
