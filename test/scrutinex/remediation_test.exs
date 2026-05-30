defmodule Scrutinex.RemediationTest do
  @moduledoc """
  Tests for all remediation items from the comprehensive review.
  Covers: bug fixes, safety improvements, new features, and missing edge cases.
  """
  use ExUnit.Case, async: true

  alias Scrutinex.{Error, Result}

  # --- Schemas ---

  defmodule SimpleSchema do
    use Scrutinex.Schema
    column("name", :string)
    column("age", :integer)
  end

  defmodule CoercionSchema do
    use Scrutinex.Schema
    column("id", :integer, coerce: true)
    column("amount", :float, coerce: true)
  end

  defmodule NullableSchema do
    use Scrutinex.Schema
    column("value", :string, nullable: true)
  end

  defmodule StrictSchema do
    use Scrutinex.Schema, strict: true
    column("name", :string)
  end

  defmodule LengthSchema do
    use Scrutinex.Schema
    column("code", :string, checks: [length: [is: 2]])
    column("name", :string, checks: [length: [min: 1, max: 10]])
  end

  defmodule RegexSchema do
    use Scrutinex.Schema
    column(~r/tag_.*/, :string)
  end

  defmodule ExclusionSchema do
    use Scrutinex.Schema
    column("status", :string, checks: [exclusion: ["banned", "blocked"]])
  end

  defmodule CrashingCheckSchema do
    use Scrutinex.Schema
    column("value", :integer, checks: [custom: &__MODULE__.crasher/1])

    def crasher(_value), do: raise(ArithmeticError, "boom")
  end

  defmodule CrashingCrossCheckSchema do
    use Scrutinex.Schema
    column("x", :integer)

    check :bad_check do
      fn _row -> raise ArithmeticError, "cross boom" end
    end
  end

  defmodule BooleanSchema do
    use Scrutinex.Schema
    column("flag", :boolean, coerce: true)
  end

  defmodule DateSchema do
    use Scrutinex.Schema
    column("date", :date, coerce: true)
  end

  defmodule DatetimeSchema do
    use Scrutinex.Schema
    column("dt", :datetime, coerce: true)
  end

  defmodule CrossCheckMissingColSchema do
    use Scrutinex.Schema
    column("x", :integer)

    check :uses_missing do
      fn row -> row["missing_col"] != nil end
    end
  end

  # --- T1-01: Length :is fast-path bug fix ---

  describe "T1-01: length :is with multibyte strings" do
    test "multibyte string where byte_size == target count fails correctly" do
      # "é" is 2 bytes, 1 grapheme. With is: 2, byte_size == 2 == count,
      # but grapheme length is 1, so it should FAIL.
      data = [%{"code" => "é", "name" => "ok"}]
      result = Scrutinex.validate(data, LengthSchema)
      refute result.valid?
      assert Enum.any?(result.errors, &(&1.check == :length and &1.column == "code"))
    end

    test "multibyte string with correct grapheme count passes" do
      # "éà" is 4 bytes, 2 graphemes. With is: 2, should pass.
      data = [%{"code" => "éà", "name" => "ok"}]
      result = Scrutinex.validate(data, LengthSchema)
      assert result.valid?
    end

    test "CJK characters counted by grapheme not bytes" do
      # "日本語" is 9 bytes, 3 graphemes
      data = [%{"code" => "日本", "name" => "ok"}]
      result = Scrutinex.validate(data, LengthSchema)
      assert result.valid?
    end

    test "emoji counted by grapheme" do
      # Single emoji is 4 bytes, 1 grapheme
      data = [%{"code" => "ab", "name" => "ok"}]
      result = Scrutinex.validate(data, LengthSchema)
      assert result.valid?
    end
  end

  # --- T1-04: Inclusion/Exclusion interpolation ---

  describe "T1-04: inclusion/exclusion error interpolation" do
    test "inclusion error message formats cleanly with commas" do
      data = [%{"status" => "deleted"}]
      result = Scrutinex.validate(data, ExclusionSchema)
      # Value "deleted" is not in exclusion list, should pass
      assert result.valid?
    end

    test "exclusion error message formats cleanly with commas" do
      data = [%{"status" => "banned"}]
      result = Scrutinex.validate(data, ExclusionSchema)
      refute result.valid?
      [error] = result.errors
      formatted = Error.format_message(error)
      assert formatted == "must not be one of banned, blocked"
    end
  end

  # --- T2-01/T2-02: Custom and cross-column check try/rescue ---

  defmodule CrashingTupleCheckSchema do
    use Scrutinex.Schema
    column("value", :integer, checks: [custom: {&__MODULE__.crasher/1, "should not see this"}])

    def crasher(_value), do: raise(ArithmeticError, "tuple boom")
  end

  describe "T2-01: custom check function crash safety" do
    test "crashing custom check produces error instead of raising" do
      data = [%{"value" => 42}]
      result = Scrutinex.validate(data, CrashingCheckSchema)
      refute result.valid?
      [error] = result.errors
      assert error.check == :custom
      assert error.message =~ "custom check raised"
    end

    test "crashing {func, message} tuple check produces error instead of raising" do
      data = [%{"value" => 42}]
      result = Scrutinex.validate(data, CrashingTupleCheckSchema)
      refute result.valid?
      [error] = result.errors
      assert error.check == :custom
      assert error.message =~ "custom check raised"
      assert error.message =~ "tuple boom"
    end
  end

  describe "T2-02: cross-column check crash safety" do
    test "crashing cross-column check produces error instead of raising" do
      data = [%{"x" => 1}]
      result = Scrutinex.validate(data, CrashingCrossCheckSchema)
      refute result.valid?
      [error] = result.errors
      assert error.check == :bad_check
      assert error.message =~ "cross-column check raised"
    end
  end

  # --- T2-03: Row-level crash isolation ---

  describe "T2-03: row-level failure isolation" do
    test "non-map row produces error but does not crash pipeline" do
      # Mix of valid maps and a non-map
      data = [%{"name" => "Alice", "age" => 30}, "not a map", %{"name" => "Bob", "age" => 25}]

      result = Scrutinex.validate(data, SimpleSchema)
      # Row 1 (the string) should produce an :internal_error
      internal = Enum.find(result.errors, &(&1.check == :internal_error))
      assert internal != nil
      assert internal.row == 1
      assert internal.message =~ "row validation failed"

      # Other rows should still be validated
      assert length(result.data) == 3
    end
  end

  # --- T2-05: Atom key handling ---

  describe "T2-05: atom key handling in regex resolution" do
    test "atom keys in data do not crash regex column resolution" do
      # Atom keys should be filtered out, not crash Regex.match?
      data = [%{:tag_color => "red", "tag_size" => "large"}]
      result = Scrutinex.validate(data, RegexSchema)
      # Should not crash; tag_size is validated, tag_color is ignored
      refute is_nil(result)
    end
  end

  # --- T2-07: Input validation ---

  describe "T2-07: input validation" do
    test "non-list input raises clear ArgumentError" do
      assert_raise ArgumentError, ~r/expected a list of maps as first argument/, fn ->
        Scrutinex.validate("not a list", SimpleSchema)
      end
    end

    test "nil input raises clear ArgumentError" do
      assert_raise ArgumentError, ~r/expected a list of maps as first argument/, fn ->
        Scrutinex.validate(nil, SimpleSchema)
      end
    end

    test "non-module second argument raises clear ArgumentError" do
      assert_raise ArgumentError, ~r/expected a schema module/, fn ->
        Scrutinex.validate([], "not a module")
      end
    end
  end

  # --- T2-09: Schema module validation ---

  describe "T2-09: schema module validation" do
    test "module without __schema__/0 raises clear error" do
      assert_raise ArgumentError, ~r/does not implement Scrutinex.Schema/, fn ->
        Scrutinex.validate([], String)
      end
    end
  end

  # --- T3-01: Conditional resolve_columns ---

  describe "T3-01: resolve_columns optimization" do
    test "schemas without regex columns still validate correctly" do
      data = [%{"name" => "Alice", "age" => 30}]
      result = Scrutinex.validate(data, SimpleSchema)
      assert result.valid?
    end

    test "schemas with regex columns still resolve correctly" do
      data = [%{"tag_color" => "red", "tag_size" => "large"}]
      result = Scrutinex.validate(data, RegexSchema)
      assert result.valid?
    end
  end

  # --- T3-03: max_errors ---

  describe "T3-03: max_errors option" do
    test "caps the returned errors at max_errors" do
      # Every row will fail with exactly 1 error (missing "name" column)
      data = for i <- 1..100, do: %{"age" => i}

      result = Scrutinex.validate(data, SimpleSchema, max_errors: 5)
      refute result.valid?
      # All 100 rows are validated (data length proves it); only the first 5
      # errors are returned because max_errors caps output, not work.
      assert length(result.errors) == 5
      assert length(result.data) == 100
    end

    test "max_errors: 1 returns exactly one error" do
      data = [%{"age" => 1}, %{"age" => 2}, %{"age" => 3}]
      result = Scrutinex.validate(data, SimpleSchema, max_errors: 1)
      refute result.valid?
      # Exactly one error returned, though all 3 rows are still validated.
      assert length(result.errors) == 1
      assert length(result.data) == 3
    end

    test "no max_errors processes all rows" do
      data = for i <- 1..10, do: %{"age" => i}
      result = Scrutinex.validate(data, SimpleSchema)
      refute result.valid?
      # Each row missing "name" = 10 errors
      assert length(result.errors) == 10
    end
  end

  defmodule MaxErrorsMixedSchema do
    use Scrutinex.Schema
    # email warns (bad format); name is default-required and errors when missing
    column("email", :string, severity: :warning, checks: [format: ~r/@/])
    column("name", :string)
  end

  defmodule MaxErrorsUniqueSchema do
    use Scrutinex.Schema
    column("email", :string, severity: :warning, checks: [format: ~r/@/])
    column("id", :string)
    unique("id")
  end

  describe "max_errors limits output, not validation" do
    test "validation runs to completion so valid? reflects rows beyond the cap" do
      # rows 0,1 each emit only a :warning (bad email); row 2 also has a real :error
      # (missing required name). Under the OLD early-halt behavior, max_errors: 2
      # was reached by the two warnings before row 2 was ever processed, so the
      # :error was missed and valid? was wrongly true.
      data = [
        %{"name" => "Alice", "email" => "bad"},
        %{"name" => "Bob", "email" => "bad"},
        %{"email" => "bad"}
      ]

      result = Scrutinex.validate(data, MaxErrorsMixedSchema, max_errors: 2)

      refute result.valid?
      assert length(result.data) == 3
    end

    test "data contains every row even when errors are capped" do
      # Each row is missing required name → 1 error per row. max_errors: 2 caps
      # the returned errors, but all 10 rows are still validated and returned.
      data = for i <- 1..10, do: %{"age" => i}

      result = Scrutinex.validate(data, SimpleSchema, max_errors: 2)

      assert length(result.errors) == 2
      assert length(result.data) == 10
      refute result.valid?
    end

    test "a duplicate beyond the cap is still detected (unique index)" do
      # rows 0,1 warn (bad email); row 2 duplicates row 0's id. Under the old
      # early-halt the two warnings hit the cap before row 2 was processed, so
      # the duplicate was invisible and valid? was wrongly true. Now validation
      # runs to completion, so the unique-index violation is detected.
      data = [
        %{"id" => "A", "email" => "bad"},
        %{"id" => "B", "email" => "bad"},
        %{"id" => "A", "email" => "ok@x"}
      ]

      result = Scrutinex.validate(data, MaxErrorsUniqueSchema, max_errors: 2)

      refute result.valid?
      assert length(result.data) == 3
    end

    test "a capped errors list surfaces the :error ahead of warnings" do
      # rows 0,1 emit only warnings (bad email); row 2 carries the invalidating
      # :error (missing required name). Even at max_errors: 1 the returned error
      # must be that :error, never a leading warning, so valid?: false is always
      # explained by the returned errors.
      data = [
        %{"name" => "Alice", "email" => "bad"},
        %{"name" => "Bob", "email" => "bad"},
        %{"email" => "bad"}
      ]

      result = Scrutinex.validate(data, MaxErrorsMixedSchema, max_errors: 1)

      refute result.valid?
      assert [%Scrutinex.Error{severity: :error}] = result.errors
    end
  end

  # --- T5-01: Meaningful error metadata ---

  describe "T5-01: error metadata for system checks" do
    test ":required error includes column in metadata" do
      data = [%{"age" => 30}]
      result = Scrutinex.validate(data, SimpleSchema)
      error = Enum.find(result.errors, &(&1.check == :required))
      assert error.metadata == %{column: "name"}
    end

    test ":not_null error includes column in metadata" do
      data = [%{"name" => nil, "age" => 30}]
      result = Scrutinex.validate(data, SimpleSchema)
      error = Enum.find(result.errors, &(&1.check == :not_null))
      assert error.metadata == %{column: "name"}
    end

    test ":unexpected_column error includes column in metadata" do
      data = [%{"name" => "Alice", "extra" => "oops"}]
      result = Scrutinex.validate(data, StrictSchema)
      error = Enum.find(result.errors, &(&1.check == :unexpected_column))
      assert error.metadata == %{column: "extra"}
    end
  end

  # --- T5-03: errors_for with check filter ---

  describe "T5-03: errors_for by check type" do
    test "filters errors by check atom" do
      data = [%{"age" => 30}]
      result = Scrutinex.validate(data, SimpleSchema)
      required_errors = Result.errors_for(result, check: :required)
      assert length(required_errors) == 1
      assert hd(required_errors).check == :required
    end

    test "returns empty list when no errors match check" do
      data = [%{"name" => "Alice", "age" => 30}]
      result = Scrutinex.validate(data, SimpleSchema)
      assert Result.errors_for(result, check: :number) == []
    end
  end

  # --- T6-02: Missing edge case tests ---

  describe "T6-02: coercion edge cases" do
    test "scientific notation float coercion" do
      data = [%{"id" => "1", "amount" => "1e5"}]
      result = Scrutinex.validate(data, CoercionSchema)
      assert result.valid?
      [row] = result.data
      assert row["amount"] == 1.0e5
    end

    test "leading whitespace fails integer coercion" do
      data = [%{"id" => " 42", "amount" => "1.0"}]
      result = Scrutinex.validate(data, CoercionSchema)
      refute result.valid?
      assert Enum.any?(result.errors, &(&1.column == "id" and &1.check == :coercion))
    end

    test "negative number coercion works" do
      data = [%{"id" => "-42", "amount" => "-3.14"}]
      result = Scrutinex.validate(data, CoercionSchema)
      assert result.valid?
      [row] = result.data
      assert row["id"] == -42
      assert row["amount"] == -3.14
    end

    test "very large integer coercion works" do
      big = "99999999999999999999999999999"
      data = [%{"id" => big, "amount" => "1.0"}]
      result = Scrutinex.validate(data, CoercionSchema)
      assert result.valid?
      [row] = result.data
      assert row["id"] == 99_999_999_999_999_999_999_999_999_999
    end

    test "uppercase boolean strings are rejected" do
      data = [%{"flag" => "TRUE"}]
      result = Scrutinex.validate(data, BooleanSchema)
      refute result.valid?
    end

    test "invalid date string is rejected" do
      data = [%{"date" => "not-a-date"}]
      result = Scrutinex.validate(data, DateSchema)
      refute result.valid?
    end

    test "non-ISO date format is rejected" do
      data = [%{"date" => "01/15/2024"}]
      result = Scrutinex.validate(data, DateSchema)
      refute result.valid?
    end

    test "invalid datetime string is rejected" do
      data = [%{"dt" => "not-a-datetime"}]
      result = Scrutinex.validate(data, DatetimeSchema)
      refute result.valid?
    end
  end

  describe "T6-02: empty map edge cases" do
    test "empty map with required columns produces :required errors" do
      data = [%{}]
      result = Scrutinex.validate(data, SimpleSchema)
      refute result.valid?
      checks = Enum.map(result.errors, & &1.check)
      assert :required in checks
    end

    test "strict mode with empty map produces only :required errors, not :unexpected_column" do
      data = [%{}]
      result = Scrutinex.validate(data, StrictSchema)
      refute result.valid?
      assert Enum.all?(result.errors, &(&1.check == :required))
    end
  end

  describe "T6-02: cross-column checks with missing columns" do
    test "cross-column check receiving nil for missing columns does not crash" do
      data = [%{"x" => 1}]
      result = Scrutinex.validate(data, CrossCheckMissingColSchema)
      refute result.valid?
      assert Enum.any?(result.errors, &(&1.check == :uses_missing))
    end
  end

  # --- T6-04: Coercion catch-all and DateTime type_check coverage ---

  describe "T6-04: coercion catch-all clauses" do
    test "coercing an atom to float returns error" do
      assert {:error, msg} = Scrutinex.Coercion.coerce(:foo, :float)
      assert msg =~ "cannot cast"
      assert msg =~ "float"
    end

    test "coercing an integer to date returns error" do
      assert {:error, msg} = Scrutinex.Coercion.coerce(42, :date)
      assert msg =~ "cannot cast"
      assert msg =~ "date"
    end

    test "coercing a list to datetime returns error" do
      assert {:error, msg} = Scrutinex.Coercion.coerce([1, 2], :datetime)
      assert msg =~ "cannot cast"
      assert msg =~ "datetime"
    end

    test "DateTime struct passes :datetime type_check" do
      {:ok, dt, _} = DateTime.from_iso8601("2024-01-15T10:30:00Z")
      assert :ok = Scrutinex.Coercion.type_check(dt, :datetime)
    end
  end

  # --- T6-05: Exclusion integration through pipeline ---

  describe "T6-05: exclusion check integration" do
    test "exclusion check works through full validation pipeline" do
      data = [%{"status" => "banned"}]
      result = Scrutinex.validate(data, ExclusionSchema)
      refute result.valid?
      [error] = result.errors
      assert error.check == :exclusion
      assert error.column == "status"
    end

    test "exclusion check passes for allowed values" do
      data = [%{"status" => "active"}]
      result = Scrutinex.validate(data, ExclusionSchema)
      assert result.valid?
    end
  end
end
