defmodule Scrutinex.UniqueIndexTest do
  use ExUnit.Case, async: true

  alias Scrutinex.{Error, Index}

  describe "schema introspection" do
    defmodule IntrospectionSchema do
      use Scrutinex.Schema

      column "region", :string
      column "sku", :string
      column "email", :string

      unique ["region", "sku"]
      unique "email"
      unique ["region", "sku"], name: :region_sku, message: "dup region/sku", severity: :warning
    end

    test "unique declarations are captured as Index structs in declaration order" do
      assert [composite, single, named] = IntrospectionSchema.__schema__().indexes

      assert %Index{
               name: :unique,
               columns: ["region", "sku"],
               message: "is a duplicate of row %{first_row}",
               severity: :error
             } = composite

      assert %Index{name: :unique, columns: ["email"], severity: :error} = single

      assert %Index{
               name: :region_sku,
               columns: ["region", "sku"],
               message: "dup region/sku",
               severity: :warning
             } = named
    end

    test "a schema without unique declarations has an empty indexes list" do
      defmodule NoIndexSchema do
        use Scrutinex.Schema
        column "a", :string
      end

      assert NoIndexSchema.__schema__().indexes == []
    end
  end

  describe "compile-time validation" do
    test "raises when an index references an undeclared column" do
      assert_raise CompileError, ~r/references undeclared column "missing"/, fn ->
        Code.compile_string("""
        defmodule UndeclaredColIndexSchema do
          use Scrutinex.Schema
          column "a", :string
          unique ["a", "missing"]
        end
        """)
      end
    end

    test "raises when an index targets a regex-declared column" do
      assert_raise CompileError, ~r/references undeclared column "score_1"/, fn ->
        Code.compile_string("""
        defmodule RegexColIndexSchema do
          use Scrutinex.Schema
          column ~r/score_.*/, :float, required: false
          unique ["score_1"]
        end
        """)
      end
    end

    test "raises when an index has an empty column list" do
      assert_raise CompileError, ~r/non-empty list/, fn ->
        Code.compile_string("""
        defmodule EmptyIndexSchema do
          use Scrutinex.Schema
          column "a", :string
          unique []
        end
        """)
      end
    end

    test "raises when an index lists a column more than once" do
      assert_raise CompileError, ~r/lists a column more than once/, fn ->
        Code.compile_string("""
        defmodule DupColIndexSchema do
          use Scrutinex.Schema
          column "a", :string
          unique ["a", "a"]
        end
        """)
      end
    end

    test "raises on invalid severity" do
      assert_raise CompileError, ~r/invalid severity/, fn ->
        Code.compile_string("""
        defmodule BadSeverityIndexSchema do
          use Scrutinex.Schema
          column "a", :string
          unique ["a"], severity: :critical
        end
        """)
      end
    end

    test "raises when unique is given a bare atom" do
      assert_raise CompileError, ~r/non-empty list of string column names/, fn ->
        Code.compile_string("""
        defmodule BareAtomIndexSchema do
          use Scrutinex.Schema
          column "email", :string
          unique :email
        end
        """)
      end
    end

    test "renders an integer column argument readably in the error" do
      assert_raise CompileError, ~r/\[123\]/, fn ->
        Code.compile_string("""
        defmodule IntegerColIndexSchema do
          use Scrutinex.Schema
          column "a", :string
          unique 123
        end
        """)
      end
    end
  end

  describe "duplicate detection" do
    defmodule CompositeSchema do
      use Scrutinex.Schema
      column "region", :string
      column "sku", :string
      unique ["region", "sku"]
    end

    defmodule SingleSchema do
      use Scrutinex.Schema
      column "email", :string
      unique "email"
    end

    test "flags only later rows whose composite tuple repeats an earlier row" do
      data = [
        %{"region" => "NA", "sku" => "X1"},
        %{"region" => "NA", "sku" => "X2"},
        %{"region" => "EU", "sku" => "X1"},
        %{"region" => "NA", "sku" => "X1"}
      ]

      result = Scrutinex.validate(data, CompositeSchema)
      assert [error] = Scrutinex.Result.errors_for(result, check: :unique)

      assert %Error{row: 3, column: nil, check: :unique, severity: :error} = error
      assert error.metadata.first_row == 0
      assert error.metadata.columns == ["region", "sku"]
      assert error.metadata.values == %{"region" => "NA", "sku" => "X1"}
      refute result.valid?
    end

    test "single-column sugar enforces single-column uniqueness" do
      data = [%{"email" => "a@x"}, %{"email" => "b@x"}, %{"email" => "a@x"}]
      result = Scrutinex.validate(data, SingleSchema)

      assert [%Error{row: 2, check: :unique}] =
               Scrutinex.Result.errors_for(result, check: :unique)
    end

    test "flags every later row in a duplicate group, all referencing the first" do
      data = [%{"email" => "a@x"}, %{"email" => "a@x"}, %{"email" => "a@x"}]
      result = Scrutinex.validate(data, SingleSchema)

      assert [%Error{row: 1} = e1, %Error{row: 2} = e2] =
               Scrutinex.Result.errors_for(result, check: :unique)

      assert e1.metadata.first_row == 0
      assert e2.metadata.first_row == 0
    end
  end

  describe "Error.format_message/1 with rich metadata" do
    test "ignores metadata whose placeholder is absent, including non-stringable values" do
      error = %Error{
        row: 1,
        column: nil,
        check: :unique,
        message: "is a duplicate of row %{first_row}",
        metadata: %{columns: ["a", "b"], first_row: 0, values: %{"a" => 1, "b" => 2}},
        value: nil
      }

      assert Error.format_message(error) == "is a duplicate of row 0"
    end

    test "interpolates a present placeholder whose value is non-stringable via inspect (no crash)" do
      error = %Error{
        row: 1,
        column: nil,
        check: :unique,
        message: "duplicate values %{values}",
        metadata: %{columns: ["a"], first_row: 0, values: %{"a" => 1}},
        value: nil
      }

      assert Error.format_message(error) == "duplicate values #{inspect(%{"a" => 1})}"
    end
  end

  describe "edge cases" do
    defmodule NullableCompositeSchema do
      use Scrutinex.Schema
      column "region", :string, required: false, on_empty: :ignore
      column "sku", :string, required: false, on_empty: :ignore
      unique ["region", "sku"]
    end

    defmodule CoercedSchema do
      use Scrutinex.Schema
      column "id", :integer, coerce: true
      unique "id"
    end

    defmodule WarnSchema do
      use Scrutinex.Schema
      column "email", :string
      unique "email", severity: :warning
    end

    defmodule MultiIndexSchema do
      use Scrutinex.Schema
      column "a", :string
      column "b", :string
      column "email", :string
      unique ["a", "b"], name: :ab
      unique "email", name: :email_unique
    end

    test "rows with any empty/nil/missing key column are excluded (SQL-null semantics)" do
      data = [
        %{"region" => nil, "sku" => "X1"},
        %{"region" => nil, "sku" => "X1"},
        %{"region" => "", "sku" => "X1"},
        %{"sku" => "X1"},
        %{"region" => "NA", "sku" => "X1"},
        %{"region" => "NA", "sku" => "X1"}
      ]

      result = Scrutinex.validate(data, NullableCompositeSchema)
      unique_errors = Scrutinex.Result.errors_for(result, check: :unique)

      assert [%Error{row: 5} = error] = unique_errors
      assert error.metadata.first_row == 4
    end

    test "uniqueness compares coerced values" do
      data = [%{"id" => "1"}, %{"id" => 1}]
      result = Scrutinex.validate(data, CoercedSchema)

      assert [%Error{row: 1} = error] = Scrutinex.Result.errors_for(result, check: :unique)
      assert error.metadata.values == %{"id" => 1}
    end

    test "a :warning-severity index does not make the result invalid" do
      data = [%{"email" => "a@x"}, %{"email" => "a@x"}]
      result = Scrutinex.validate(data, WarnSchema)

      assert result.valid?

      assert [%Error{row: 1, severity: :warning}] =
               Scrutinex.Result.errors_for(result, check: :unique)
    end

    test "multiple indexes are evaluated independently and keyed by name" do
      data = [
        %{"a" => "1", "b" => "2", "email" => "x@y"},
        %{"a" => "1", "b" => "2", "email" => "z@y"},
        %{"a" => "9", "b" => "9", "email" => "x@y"}
      ]

      result = Scrutinex.validate(data, MultiIndexSchema)

      assert [%Error{row: 1, check: :ab}] = Scrutinex.Result.errors_for(result, check: :ab)

      assert [%Error{row: 2, check: :email_unique}] =
               Scrutinex.Result.errors_for(result, check: :email_unique)
    end
  end

  describe "coercion and type-check interaction" do
    defmodule CoerceFailSchema do
      use Scrutinex.Schema
      column "id", :integer, coerce: true
      unique "id"
    end

    defmodule TypeFailSchema do
      use Scrutinex.Schema
      column "id", :integer
      unique "id"
    end

    defmodule NegativeCoerceSchema do
      use Scrutinex.Schema
      column "id", :integer, coerce: true, checks: [number: [greater_than: 0]]
      unique "id"
    end

    test "a row whose indexed column fails coercion is excluded from the index" do
      data = [%{"id" => "abc"}, %{"id" => "abc"}]
      result = Scrutinex.validate(data, CoerceFailSchema)

      assert Scrutinex.Result.errors_for(result, check: :unique) == []

      assert [%Error{row: 0, check: :coercion}, %Error{row: 1, check: :coercion}] =
               Scrutinex.Result.errors_for(result, check: :coercion)

      refute result.valid?
    end

    test "a row whose indexed column fails type-checking (coerce: false) is excluded from the index" do
      data = [%{"id" => "abc"}, %{"id" => "abc"}]
      result = Scrutinex.validate(data, TypeFailSchema)

      assert Scrutinex.Result.errors_for(result, check: :unique) == []

      assert [%Error{row: 0, check: :type}, %Error{row: 1, check: :type}] =
               Scrutinex.Result.errors_for(result, check: :type)

      refute result.valid?
    end

    test "a row that coerces successfully still participates even if it fails a column check" do
      data = [%{"id" => "-5"}, %{"id" => "-5"}]
      result = Scrutinex.validate(data, NegativeCoerceSchema)

      assert [%Error{row: 0, check: :number}, %Error{row: 1, check: :number}] =
               Scrutinex.Result.errors_for(result, check: :number)

      assert [%Error{row: 1, check: :unique} = unique_error] =
               Scrutinex.Result.errors_for(result, check: :unique)

      assert unique_error.metadata.first_row == 0
      assert unique_error.metadata.values == %{"id" => -5}
    end
  end

  describe "falsy-but-present values participate (not skipped by the null rule)" do
    defmodule BoolSchema do
      use Scrutinex.Schema
      column "flag", :boolean
      unique "flag"
    end

    defmodule ZeroIntSchema do
      use Scrutinex.Schema
      column "n", :integer
      unique "n"
    end

    defmodule ZeroFloatSchema do
      use Scrutinex.Schema
      column "n", :float
      unique "n"
    end

    test "false is a present value and duplicates are flagged" do
      data = [%{"flag" => false}, %{"flag" => false}]
      result = Scrutinex.validate(data, BoolSchema)

      assert [%Error{row: 1} = error] = Scrutinex.Result.errors_for(result, check: :unique)
      assert error.metadata.values == %{"flag" => false}
    end

    test "integer 0 is a present value and duplicates are flagged" do
      data = [%{"n" => 0}, %{"n" => 0}]
      result = Scrutinex.validate(data, ZeroIntSchema)

      assert [%Error{row: 1}] = Scrutinex.Result.errors_for(result, check: :unique)
    end

    test "float 0.0 is a present value and duplicates are flagged" do
      data = [%{"n" => 0.0}, %{"n" => 0.0}]
      result = Scrutinex.validate(data, ZeroFloatSchema)

      assert [%Error{row: 1}] = Scrutinex.Result.errors_for(result, check: :unique)
    end
  end

  describe "non-indexed columns" do
    defmodule NonIndexedColSchema do
      use Scrutinex.Schema
      column "id", :string
      column "note", :string
      unique "id"
    end

    test "a duplicate in a non-indexed column is not flagged" do
      data = [%{"id" => "a", "note" => "same"}, %{"id" => "b", "note" => "same"}]
      result = Scrutinex.validate(data, NonIndexedColSchema)

      assert Scrutinex.Result.errors_for(result, check: :unique) == []
      assert result.valid?
    end
  end

  describe "struct-valued indexed columns" do
    defmodule DateSchema do
      use Scrutinex.Schema
      column "d", :date
      unique "d"
    end

    test "a %Date{} struct-valued indexed column detects duplicates" do
      data = [
        %{"d" => ~D[2024-01-01]},
        %{"d" => ~D[2024-01-01]},
        %{"d" => ~D[2024-06-01]}
      ]

      result = Scrutinex.validate(data, DateSchema)

      assert [%Error{row: 1} = e] = Scrutinex.Result.errors_for(result, check: :unique)
      assert e.metadata.values == %{"d" => ~D[2024-01-01]}
    end
  end

  describe "end-to-end rendering of the duplicate error" do
    defmodule RenderSchema do
      use Scrutinex.Schema
      column "email", :string
      unique "email"
    end

    test "the produced duplicate error renders through format_message and errors_to_map" do
      data = [%{"email" => "a@x"}, %{"email" => "a@x"}]
      result = Scrutinex.validate(data, RenderSchema)

      assert [%Error{} = unique_error] = Scrutinex.Result.errors_for(result, check: :unique)
      assert Error.format_message(unique_error) == "is a duplicate of row 0"

      map = Scrutinex.Result.errors_to_map(result)
      assert "is a duplicate of row 0" in Map.fetch!(map, nil)
    end
  end

  describe "malformed (non-map) rows" do
    defmodule MalformedRowSchema do
      use Scrutinex.Schema
      column "id", :integer
      unique "id"
    end

    test "a non-map row does not crash the unique pass and is reported as an internal error" do
      data = [%{"id" => 1}, "not a map", %{"id" => 1}]
      result = Scrutinex.validate(data, MalformedRowSchema)

      assert [%Error{row: 1, check: :internal_error}] =
               Scrutinex.Result.errors_for(result, check: :internal_error)

      # the non-map row is skipped by the index; the two valid id=1 rows still
      # produce a duplicate, and the skipped row does not disturb first_row
      assert [%Error{row: 2, check: :unique} = dup] =
               Scrutinex.Result.errors_for(result, check: :unique)

      assert dup.metadata.first_row == 0
      refute result.valid?
    end
  end
end
