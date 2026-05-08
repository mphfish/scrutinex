defmodule Scrutinex.SeverityTest do
  use ExUnit.Case, async: true

  alias Scrutinex.{Error, Result}

  # --- Schemas for testing severity features ---

  defmodule ColumnSeveritySchema do
    use Scrutinex.Schema

    # column-level severity: :warning — all errors from this column inherit it
    column "email", :string, severity: :warning, checks: [format: ~r/@/]
    column "name", :string, checks: [length: [min: 1]]
  end

  defmodule PerCheckSeveritySchema do
    use Scrutinex.Schema

    # per-check severity overrides column-level
    column "email", :string,
      severity: :error,
      checks: [format: {~r/@/, severity: :warning}]

    column "name", :string, checks: [length: {[min: 1], severity: :warning}]
  end

  defmodule CrossColumnSeveritySchema do
    use Scrutinex.Schema

    column "start", :string
    column "end", :string

    check :ordering, severity: :warning do
      fn row -> row["start"] < row["end"] end
    end
  end

  defmodule MixedSeveritySchema do
    use Scrutinex.Schema

    column "name", :string
    column "email", :string, severity: :warning, checks: [format: ~r/@/]
  end

  defmodule MaxErrorsSchema do
    use Scrutinex.Schema

    column "email", :string, severity: :warning, checks: [format: ~r/@/]
    column "name", :string, checks: [length: [min: 1]]
  end

  defmodule WarnOnlySchema do
    use Scrutinex.Schema

    column "email", :string, severity: :warning, checks: [format: ~r/@/]
  end

  # --- AC1: Error struct has severity field with :error default ---

  describe "AC1: Error struct severity field" do
    test "default severity is :error" do
      error = %Error{row: 0, check: :required, message: "is required"}
      assert error.severity == :error
    end

    test "severity can be set to :warning" do
      error = %Error{row: 0, check: :format, message: "invalid format", severity: :warning}
      assert error.severity == :warning
    end
  end

  # --- AC2: Column-level severity inherited by all errors from that column ---

  describe "AC2: Column-level severity" do
    test "errors from a :warning column have severity :warning" do
      data = [%{"email" => "not-an-email", "name" => "Alice"}]
      result = Scrutinex.validate(data, ColumnSeveritySchema)

      email_errors = Result.errors_for(result, "email")
      assert length(email_errors) == 1
      assert hd(email_errors).severity == :warning
    end

    test "errors from a default (no severity option) column have severity :error" do
      data = [%{"email" => "alice@example.com", "name" => ""}]
      result = Scrutinex.validate(data, ColumnSeveritySchema)

      name_errors = Result.errors_for(result, "name")
      assert length(name_errors) == 1
      assert hd(name_errors).severity == :error
    end

    test "not_null error from a :warning column inherits column severity" do
      data = [%{"email" => nil, "name" => "Alice"}]
      result = Scrutinex.validate(data, ColumnSeveritySchema)

      email_errors = Result.errors_for(result, "email")
      assert length(email_errors) == 1
      assert hd(email_errors).severity == :warning
    end
  end

  # --- AC3: Per-check severity overrides column-level ---

  describe "AC3: Per-check severity" do
    test "per-check severity :warning on format check" do
      data = [%{"email" => "not-an-email", "name" => "Alice"}]
      result = Scrutinex.validate(data, PerCheckSeveritySchema)

      email_errors = Result.errors_for(result, "email")
      assert length(email_errors) == 1
      assert hd(email_errors).severity == :warning
    end

    test "per-check severity on length check" do
      # "x" passes not_null but fails length min: 1 since length is 1... use empty check differently
      # We need a value that passes null check but fails the length check.
      # But length: [min: 1] would pass for any non-empty value of length >= 1.
      # Use a separate schema with min: 2 to test this path.
      defmodule LengthPerCheckSchema do
        use Scrutinex.Schema
        column "name", :string, checks: [length: {[min: 2], severity: :warning}]
      end

      data = [%{"name" => "x"}]
      result = Scrutinex.validate(data, LengthPerCheckSchema)

      name_errors = Result.errors_for(result, "name")
      assert length(name_errors) == 1
      assert hd(name_errors).severity == :warning
    end
  end

  # --- AC4: Per-check severity precedence: per-check > column-level > :error default ---

  describe "AC4: Severity precedence" do
    test "per-check :warning overrides column-level :error" do
      data = [%{"email" => "not-an-email", "name" => "Alice"}]
      result = Scrutinex.validate(data, PerCheckSeveritySchema)

      email_errors = Result.errors_for(result, "email")
      assert length(email_errors) == 1
      # The column has severity: :error, but the format check has per-check severity: :warning
      assert hd(email_errors).severity == :warning
    end
  end

  # --- AC5: Cross-column check severity ---

  describe "AC5: Cross-column check severity" do
    test "cross-column check with :warning produces warning-severity error" do
      data = [%{"start" => "2024-12-31", "end" => "2024-01-01"}]
      result = Scrutinex.validate(data, CrossColumnSeveritySchema)

      cross_errors = Enum.filter(result.errors, &(&1.check == :ordering))
      assert length(cross_errors) == 1
      assert hd(cross_errors).severity == :warning
    end
  end

  # --- AC6: Result.valid? == true when all errors are :warning ---

  describe "AC6: valid? with only warnings" do
    test "valid? is true when all errors are :warning severity" do
      data = [%{"email" => "not-an-email"}]
      result = Scrutinex.validate(data, WarnOnlySchema)

      assert length(result.errors) == 1
      assert hd(result.errors).severity == :warning
      assert result.valid? == true
    end
  end

  # --- AC7: Result.valid? == false when any error is :error severity ---

  describe "AC7: valid? with any :error severity" do
    test "valid? is false when any error is :error severity" do
      data = [%{"email" => "not-an-email", "name" => ""}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      assert Enum.any?(result.errors, &(&1.severity == :error))
      assert result.valid? == false
    end

    test "valid? is false with only :error severity errors" do
      data = [%{"name" => "", "email" => "alice@example.com"}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      refute result.valid?
    end
  end

  # --- AC8: max_errors counts ALL errors regardless of severity ---

  describe "AC8: max_errors counts all severities" do
    test "max_errors halts after N total errors including warnings" do
      # WarnOnlySchema has only a :warning column, so all errors are warnings.
      # With max_errors: 2 and each row producing 1 warning, we stop after 2 rows.
      data = Enum.map(1..10, fn _ -> %{"email" => "bad-email"} end)
      result = Scrutinex.validate(data, WarnOnlySchema, max_errors: 2)

      # max_errors counts warnings too — stopped after 2 warnings
      assert length(result.errors) == 2
      assert Enum.all?(result.errors, &(&1.severity == :warning))
    end

    test "max_errors with mixed severity halts on total count" do
      # MixedSeveritySchema: email = :warning, name = :error.
      # Each row produces 1 warning (email) + 1 error (name).
      # max_errors: 2 → after row 0 count=2 >= 2, halt → only row 0's errors
      data = [
        %{"email" => "bad", "name" => ""},
        %{"email" => "bad", "name" => ""},
        %{"email" => "bad", "name" => ""}
      ]

      result = Scrutinex.validate(data, MixedSeveritySchema, max_errors: 2)

      # Exactly 2 errors from row 0 (1 warning + 1 error)
      assert length(result.errors) == 2
    end
  end

  # --- AC9: validate!/2 counts only :error severity errors ---

  describe "AC9: validate!/2 with warnings" do
    test "validate!/2 raises with only :error severity count in message" do
      data = [%{"email" => "not-an-email", "name" => ""}]

      assert_raise Scrutinex.ValidationError, ~r/1 error/, fn ->
        Scrutinex.validate!(data, MixedSeveritySchema)
      end
    end

    test "validate!/2 does not raise when only warnings present" do
      data = [%{"email" => "not-an-email"}]
      rows = Scrutinex.validate!(data, WarnOnlySchema)
      assert rows == data
    end
  end

  # --- AC10: Result.warnings/1 returns only :warning errors ---

  describe "AC10: Result.warnings/1" do
    test "returns only :warning severity errors" do
      data = [%{"email" => "not-an-email", "name" => ""}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      warnings = Result.warnings(result)
      assert Enum.all?(warnings, &(&1.severity == :warning))
      assert length(warnings) == 1
    end

    test "returns empty list when no warnings" do
      data = [%{"email" => "alice@example.com", "name" => "Alice"}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      assert Result.warnings(result) == []
    end
  end

  # --- AC11: Result.errors_only/1 returns only :error severity errors ---

  describe "AC11: Result.errors_only/1" do
    test "returns only :error severity errors" do
      data = [%{"email" => "not-an-email", "name" => ""}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      errors_only = Result.errors_only(result)
      assert Enum.all?(errors_only, &(&1.severity == :error))
      assert length(errors_only) == 1
    end

    test "returns empty list when no :error severity errors" do
      data = [%{"email" => "not-an-email"}]
      result = Scrutinex.validate(data, WarnOnlySchema)

      assert Result.errors_only(result) == []
    end
  end

  # --- AC12: Result.errors_for(result, severity: :warning) ---

  describe "AC12: errors_for/2 with severity filter" do
    test "errors_for with severity: :warning returns only warnings" do
      data = [%{"email" => "not-an-email", "name" => ""}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      warnings = Result.errors_for(result, severity: :warning)
      assert Enum.all?(warnings, &(&1.severity == :warning))
      assert length(warnings) == 1
    end

    test "errors_for with severity: :error returns only errors" do
      data = [%{"email" => "not-an-email", "name" => ""}]
      result = Scrutinex.validate(data, MixedSeveritySchema)

      errors = Result.errors_for(result, severity: :error)
      assert Enum.all?(errors, &(&1.severity == :error))
      assert length(errors) == 1
    end
  end

  # --- AC13: Backward compatibility — no severity means :error ---

  describe "AC13: Backward compatibility" do
    test "existing schemas without severity produce :error by default" do
      defmodule LegacySchema do
        use Scrutinex.Schema

        column "name", :string, checks: [length: [min: 1]]
      end

      data = [%{"name" => ""}]
      result = Scrutinex.validate(data, LegacySchema)

      assert length(result.errors) == 1
      assert hd(result.errors).severity == :error
      refute result.valid?
    end

    test "cross-column checks without severity default to :error" do
      defmodule LegacyCrossSchema do
        use Scrutinex.Schema

        column "x", :string
        column "y", :string

        check :must_differ do
          fn row -> row["x"] != row["y"] end
        end
      end

      data = [%{"x" => "a", "y" => "a"}]
      result = Scrutinex.validate(data, LegacyCrossSchema)

      cross_errors = Enum.filter(result.errors, &(&1.check == :must_differ))
      assert length(cross_errors) == 1
      assert hd(cross_errors).severity == :error
    end
  end
end
