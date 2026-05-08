defmodule Scrutinex.RegexRequiredTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Error

  # Schema with a required regex column (explicit required: true)
  defmodule RequiredRegexSchema do
    use Scrutinex.Schema

    column "name", :string
    column ~r/^score_/, :float, required: true, nullable: true
  end

  # Schema with a non-required regex column (explicit required: false)
  defmodule OptionalRegexSchema do
    use Scrutinex.Schema

    column "name", :string
    column ~r/^tag_/, :string, required: false, nullable: true
  end

  # Schema with a regex column using the implicit default
  defmodule DefaultRegexSchema do
    use Scrutinex.Schema

    column "name", :string
    column ~r/^metric_/, :float, nullable: true
  end

  describe "required: true regex column with matching columns" do
    test "produces no error when at least one column matches the pattern" do
      data = [%{"name" => "Alice", "score_math" => 95.0}]
      result = Scrutinex.validate(data, RequiredRegexSchema)

      refute Enum.any?(result.errors, fn e -> e.check == :required_columns end)
      assert result.valid?
    end

    test "produces no error when multiple columns match the pattern" do
      data = [%{"name" => "Bob", "score_math" => 88.0, "score_science" => 92.0}]
      result = Scrutinex.validate(data, RequiredRegexSchema)

      refute Enum.any?(result.errors, fn e -> e.check == :required_columns end)
      assert result.valid?
    end
  end

  describe "required: true regex column with zero matching columns" do
    test "produces a schema-level error with row: nil" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, RequiredRegexSchema)

      regex_errors = Enum.filter(result.errors, fn e -> e.check == :required_columns end)
      assert length(regex_errors) == 1

      [error] = regex_errors
      assert error.row == nil
      assert error.severity == :error
    end

    test "error message includes the regex pattern source" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, RequiredRegexSchema)

      [error] = Enum.filter(result.errors, fn e -> e.check == :required_columns end)
      formatted = Error.format_message(error)
      assert formatted =~ "score_"
    end

    test "result is not valid" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, RequiredRegexSchema)

      refute result.valid?
    end
  end

  describe "required: false regex column (explicit)" do
    test "produces no error when no column matches" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, OptionalRegexSchema)

      refute Enum.any?(result.errors, fn e -> e.check == :required_columns end)
      assert result.valid?
    end
  end

  describe "regex column without required option defaults to required: false" do
    test "produces no error when no column matches (backward compatible)" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, DefaultRegexSchema)

      refute Enum.any?(result.errors, fn e -> e.check == :required_columns end)
      assert result.valid?
    end
  end

  describe "named string column without required option defaults to required: true" do
    defmodule NamedDefaultSchema do
      use Scrutinex.Schema

      column "name", :string
    end

    test "named column is required by default" do
      schema = NamedDefaultSchema.__schema__()
      [col] = schema.columns
      assert col.required == true
    end
  end

  describe "zero-row dataset with required regex column" do
    test "still produces the required regex error" do
      data = []
      result = Scrutinex.validate(data, RequiredRegexSchema)

      regex_errors = Enum.filter(result.errors, fn e -> e.check == :required_columns end)
      assert length(regex_errors) == 1
      refute result.valid?
    end
  end

  describe "Error struct row field" do
    test "row is nil for schema-level required regex errors" do
      data = [%{"name" => "Alice"}]
      result = Scrutinex.validate(data, RequiredRegexSchema)

      [error] = Enum.filter(result.errors, fn e -> e.check == :required_columns end)
      assert is_nil(error.row)
    end
  end

  describe "schema default for required field" do
    test "regex column defaults to required: false" do
      schema = DefaultRegexSchema.__schema__()
      regex_col = Enum.find(schema.columns, fn col -> match?(%Regex{}, col.name) end)
      assert regex_col.required == false
    end

    test "named column defaults to required: true" do
      schema = DefaultRegexSchema.__schema__()
      named_col = Enum.find(schema.columns, fn col -> is_binary(col.name) end)
      assert named_col.required == true
    end
  end
end
