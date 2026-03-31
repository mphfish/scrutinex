defmodule Scrutinex.SchemaTest do
  use ExUnit.Case, async: true

  alias Scrutinex.{Column, Check}

  defmodule SimpleSchema do
    use Scrutinex.Schema

    column("name", :string, required: true)
    column("age", :integer, coerce: true, checks: [number: [greater_than: 0]])
  end

  defmodule StrictSchema do
    use Scrutinex.Schema, strict: true

    column("id", :integer)
  end

  defmodule RegexSchema do
    use Scrutinex.Schema

    column(~r/sales_.*/, :float, coerce: true, checks: [number: [greater_than_or_equal_to: 0]])
  end

  defmodule CrossColumnSchema do
    use Scrutinex.Schema

    column("start_date", :string)
    column("end_date", :string)

    check :dates_ordered do
      fn row -> row["start_date"] < row["end_date"] end
    end

    check :custom_check, message: "custom message" do
      fn row -> row["start_date"] != nil end
    end
  end

  describe "column macro" do
    test "defines columns with correct attributes" do
      schema = SimpleSchema.__schema__()
      assert length(schema.columns) == 2

      [name_col, age_col] = schema.columns
      assert %Column{name: "name", type: :string, required: true, coerce: false} = name_col

      assert %Column{
               name: "age",
               type: :integer,
               coerce: true,
               checks: [number: [greater_than: 0]]
             } = age_col
    end

    test "supports regex column names" do
      schema = RegexSchema.__schema__()
      [col] = schema.columns
      assert %Column{name: %Regex{}, type: :float, coerce: true} = col
      assert Regex.match?(col.name, "sales_q1")
    end
  end

  describe "strict option" do
    test "sets strict flag on schema" do
      schema = StrictSchema.__schema__()
      assert schema.strict == true
    end

    test "defaults strict to false" do
      schema = SimpleSchema.__schema__()
      assert schema.strict == false
    end
  end

  describe "compile-time validation" do
    test "raises CompileError for invalid column type" do
      assert_raise CompileError, ~r/invalid column type :invalid_type/, fn ->
        Code.compile_string("""
        defmodule InvalidTypeSchema do
          use Scrutinex.Schema
          column "x", :invalid_type
        end
        """)
      end
    end

    test "raises CompileError for invalid check name" do
      assert_raise CompileError, ~r/unknown check :nonexistent/, fn ->
        Code.compile_string("""
        defmodule InvalidCheckSchema do
          use Scrutinex.Schema
          column "x", :string, checks: [nonexistent: []]
        end
        """)
      end
    end

    test "allows all valid types" do
      Code.compile_string("""
      defmodule AllTypesSchema do
        use Scrutinex.Schema
        column "a", :string
        column "b", :integer
        column "c", :float
        column "d", :boolean
        column "e", :date
        column "f", :datetime
      end
      """)
    end

    test "allows all valid check names" do
      Code.compile_string("""
      defmodule AllChecksSchema do
        use Scrutinex.Schema
        column "a", :string, checks: [inclusion: ["x"]]
        column "b", :string, checks: [exclusion: ["x"]]
        column "c", :string, checks: [format: ~r/x/]
        column "d", :string, checks: [length: [min: 1]]
        column "e", :integer, checks: [number: [greater_than: 0]]
        column "f", :integer, checks: [custom: &is_integer/1]
      end
      """)
    end
  end

  describe "check macro" do
    test "defines cross-column checks" do
      schema = CrossColumnSchema.__schema__()
      assert length(schema.checks) == 2

      [dates_check, custom_check] = schema.checks
      assert %Check{name: :dates_ordered, message: "check failed"} = dates_check
      assert is_function(dates_check.function, 1)
      assert %Check{name: :custom_check, message: "custom message"} = custom_check
    end

    test "check functions receive the row and return boolean" do
      schema = CrossColumnSchema.__schema__()
      [dates_check | _] = schema.checks

      assert dates_check.function.(%{"start_date" => "2024-01-01", "end_date" => "2024-12-31"})
      refute dates_check.function.(%{"start_date" => "2024-12-31", "end_date" => "2024-01-01"})
    end
  end
end
