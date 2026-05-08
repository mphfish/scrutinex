defmodule Scrutinex.FuzzySuggestionTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Error

  defmodule SuggestionSchema do
    use Scrutinex.Schema, strict: true

    column("store_id", :string, required: false)
    column("product_name", :string, required: false)
    column("amount", :float, required: false)
  end

  defmodule RegexSuggestionSchema do
    use Scrutinex.Schema, strict: true

    column("id", :integer)
    column(~r/sales_.*/, :float, coerce: true)
  end

  describe "fuzzy column suggestions in strict mode" do
    # Acceptance criterion 1: typo "stor_id" with schema "store_id" gets suggestion
    test "typo column includes closest match in metadata" do
      data = [%{"stor_id" => "abc"}]
      result = Scrutinex.validate(data, SuggestionSchema)
      refute result.valid?

      [error] = result.errors
      assert error.check == :unexpected_column
      assert error.metadata[:suggestion] == "store_id"
    end

    # Acceptance criterion 2: Jaro distance >= 0.8 triggers suggestion
    test "jaro distance >= 0.8 includes suggestion" do
      # "stor_id" vs "store_id": distance is above 0.8
      data = [%{"stor_id" => "abc"}]
      result = Scrutinex.validate(data, SuggestionSchema)

      [error] = result.errors
      score = String.jaro_distance("stor_id", "store_id")
      assert score >= 0.8
      assert error.metadata[:suggestion] == "store_id"
    end

    # Acceptance criterion 3: Jaro distance < 0.8 — no suggestion
    test "very different column name has no suggestion" do
      data = [%{"zzz_unrelated" => "abc"}]
      result = Scrutinex.validate(data, SuggestionSchema)
      refute result.valid?

      [error] = result.errors
      assert error.check == :unexpected_column
      refute Map.has_key?(error.metadata, :suggestion)
    end

    # Acceptance criterion 4: multiple candidates above threshold — highest score wins
    test "picks highest jaro score when multiple candidates qualify" do
      # "product_nme" is closer to "product_name" than "store_id" or "amount"
      data = [%{"product_nme" => "widget"}]
      result = Scrutinex.validate(data, SuggestionSchema)
      refute result.valid?

      [error] = result.errors
      assert error.metadata[:suggestion] == "product_name"
    end

    # Acceptance criterion 6: error message includes suggestion when present
    test "error message template references suggestion when close match exists" do
      data = [%{"stor_id" => "abc"}]
      result = Scrutinex.validate(data, SuggestionSchema)

      [error] = result.errors
      formatted = Error.format_message(error)
      assert formatted =~ "store_id"
    end

    # Acceptance criterion 7: error message unchanged when no suggestion
    test "error message is plain 'unexpected column' when no close match" do
      data = [%{"zzz_unrelated" => "abc"}]
      result = Scrutinex.validate(data, SuggestionSchema)

      [error] = result.errors
      assert error.message == "unexpected column"
    end

    # Acceptance criterion 8: does NOT fire on :required column errors
    test "required column errors have no suggestion" do
      # RequiredStrictSchema has "store_id" required (default) and strict: true
      # Passing only an unexpected column triggers both required + unexpected_column errors
      defmodule RequiredStrictSchema do
        use Scrutinex.Schema, strict: true
        column("store_id", :string)
      end

      data = [%{"stor_id" => "abc"}]
      result = Scrutinex.validate(data, RequiredStrictSchema)
      refute result.valid?

      required_errors = Enum.filter(result.errors, &(&1.check == :required))
      assert length(required_errors) > 0

      for err <- required_errors do
        refute Map.has_key?(err.metadata, :suggestion)
      end
    end

    # Acceptance criterion 9: suggestions cached — same unexpected key reuses suggestion
    test "same unexpected column across multiple rows gets same suggestion" do
      data = [
        %{"stor_id" => "a"},
        %{"stor_id" => "b"},
        %{"stor_id" => "c"}
      ]

      result = Scrutinex.validate(data, SuggestionSchema)
      refute result.valid?

      strict_errors = Enum.filter(result.errors, &(&1.check == :unexpected_column))
      assert length(strict_errors) == 3

      suggestions = Enum.map(strict_errors, & &1.metadata[:suggestion])
      assert Enum.all?(suggestions, &(&1 == "store_id"))
    end

    # Acceptance criterion 5: regex-resolved columns excluded from candidate pool
    test "regex-resolved column names excluded from suggestion candidates" do
      # "sales_q99" would match ~r/sales_.*/ so it should NOT appear as a suggestion
      # An unresolved key like "saless_q1" should NOT suggest "sales_q1" (a regex-resolved name)
      data = [%{"id" => 1, "extra_col" => 99}]
      result = Scrutinex.validate(data, RegexSuggestionSchema)
      refute result.valid?

      [error] = result.errors
      assert error.check == :unexpected_column
      # "id" is declared; "extra_col" is unexpected — it has no close match to "id"
      refute Map.has_key?(error.metadata, :suggestion)
    end

    # Acceptance criterion 10: backward compatible — no close match leaves error unchanged
    test "backward compatible: existing strict errors unchanged when no close match" do
      data = [%{"name" => "Alice", "xyz_totally_different_col" => "oops"}]

      defmodule SimpleStrictSchema do
        use Scrutinex.Schema, strict: true
        column("name", :string)
      end

      result = Scrutinex.validate(data, SimpleStrictSchema)
      refute result.valid?

      [error] = result.errors
      assert error.check == :unexpected_column
      assert error.column == "xyz_totally_different_col"
      assert error.message == "unexpected column"
      assert error.metadata == %{column: "xyz_totally_different_col"}
    end
  end
end
