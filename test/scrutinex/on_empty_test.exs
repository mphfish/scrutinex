defmodule Scrutinex.OnEmptyTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Error

  defmodule WarnSchema do
    use Scrutinex.Schema

    column("required_field", :string)
    column("optional_field", :string, on_empty: :warn, checks: [length: [min: 1]])
  end

  defmodule IgnoreSchema do
    use Scrutinex.Schema

    column("required_field", :string)
    column("optional_field", :string, on_empty: :ignore, checks: [length: [min: 1]])
  end

  defmodule ErrorSchema do
    use Scrutinex.Schema

    column("required_field", :string)
    column("optional_field", :string, on_empty: :error)
  end

  defmodule NullableSugarSchema do
    use Scrutinex.Schema

    column("required_field", :string)
    column("optional_field", :string, nullable: true, checks: [length: [min: 1]])
  end

  defmodule CoerceWarnSchema do
    use Scrutinex.Schema

    column("amount", :integer, on_empty: :warn, coerce: true)
  end

  describe "on_empty: :warn" do
    test "empty value produces a warning error and result remains valid?" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, WarnSchema)
      assert result.valid?

      assert [%Error{severity: :warning, check: :empty_value, column: "optional_field"}] =
               result.errors
    end

    test "empty string also triggers :warn" do
      data = [%{"required_field" => "hello", "optional_field" => ""}]
      result = Scrutinex.validate(data, WarnSchema)
      assert result.valid?
      assert [%Error{severity: :warning, check: :empty_value}] = result.errors
    end

    test "column checks are skipped when on_empty: :warn" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, WarnSchema)
      # only the :empty_value warning, not a :length check error
      assert length(result.errors) == 1
      assert hd(result.errors).check == :empty_value
    end

    test "result.data contains nil for :warn cell" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, WarnSchema)
      [row] = result.data
      assert row["optional_field"] == nil
    end

    test "coercion does not run on empty value when on_empty: :warn" do
      data = [%{"amount" => nil}]
      result = Scrutinex.validate(data, CoerceWarnSchema)
      assert result.valid?
      assert [%Error{check: :empty_value, severity: :warning}] = result.errors
    end
  end

  describe "on_empty: :ignore" do
    test "empty value produces no error" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, IgnoreSchema)
      assert result.valid?
      assert result.errors == []
    end

    test "empty string produces no error" do
      data = [%{"required_field" => "hello", "optional_field" => ""}]
      result = Scrutinex.validate(data, IgnoreSchema)
      assert result.valid?
      assert result.errors == []
    end

    test "column checks are skipped when on_empty: :ignore" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, IgnoreSchema)
      assert result.errors == []
    end

    test "result.data contains nil for :ignore cell" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, IgnoreSchema)
      [row] = result.data
      assert row["optional_field"] == nil
    end
  end

  describe "on_empty: :error (default)" do
    test "empty value produces severity :error" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, ErrorSchema)
      refute result.valid?
      assert [%Error{severity: :error, check: :not_null}] = result.errors
    end

    test "default on_empty: :error preserves existing behavior" do
      defmodule DefaultSchema do
        use Scrutinex.Schema

        column("field", :string)
      end

      data = [%{"field" => nil}]
      result = Scrutinex.validate(data, DefaultSchema)
      refute result.valid?
      assert [%Error{check: :not_null, severity: :error}] = result.errors
    end
  end

  describe "nullable: true as sugar for on_empty: :ignore" do
    test "nullable: true behaves like on_empty: :ignore" do
      data = [%{"required_field" => "hello", "optional_field" => nil}]
      result = Scrutinex.validate(data, NullableSugarSchema)
      assert result.valid?
      assert result.errors == []
    end

    test "nullable: true skips column checks on empty values" do
      data = [%{"required_field" => "hello", "optional_field" => ""}]
      result = Scrutinex.validate(data, NullableSugarSchema)
      assert result.valid?
      assert result.errors == []
    end
  end

  describe "compile-time validation" do
    test "raises CompileError when both nullable and on_empty are set" do
      assert_raise CompileError, ~r/cannot set both :nullable and :on_empty/, fn ->
        Code.compile_string("""
        defmodule BothOptionsSchema do
          use Scrutinex.Schema
          column "field", :string, nullable: true, on_empty: :warn
        end
        """)
      end
    end

    test "raises CompileError for invalid on_empty value" do
      assert_raise CompileError, ~r/invalid on_empty value :nope/, fn ->
        Code.compile_string("""
        defmodule BadOnEmptySchema do
          use Scrutinex.Schema
          column "field", :string, on_empty: :nope
        end
        """)
      end
    end
  end
end
