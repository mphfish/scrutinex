defmodule Scrutinex.ResultTest do
  use ExUnit.Case, async: true

  alias Scrutinex.{Error, Result}

  describe "errors_for/2 with column name" do
    test "returns errors matching the given column" do
      errors = [
        %Error{
          row: 0,
          column: "amount",
          check: :number,
          message: "too low",
          metadata: %{},
          value: -1
        },
        %Error{
          row: 1,
          column: "name",
          check: :length,
          message: "too short",
          metadata: %{},
          value: ""
        },
        %Error{
          row: 2,
          column: "amount",
          check: :number,
          message: "too low",
          metadata: %{},
          value: -5
        }
      ]

      result = %Result{valid?: false, data: [], errors: errors}

      assert [%Error{row: 0, column: "amount"}, %Error{row: 2, column: "amount"}] =
               Result.errors_for(result, "amount")
    end

    test "returns empty list when no errors match column" do
      result = %Result{valid?: true, data: [], errors: []}
      assert [] == Result.errors_for(result, "amount")
    end
  end

  describe "errors_to_map/1" do
    test "groups errors by column with formatted messages" do
      errors = [
        %Error{
          row: 0,
          column: "age",
          check: :number,
          message: "must be greater than %{number}",
          metadata: %{number: 0},
          value: -1
        },
        %Error{
          row: 0,
          column: "name",
          check: :required,
          message: "is required",
          metadata: %{},
          value: nil
        },
        %Error{
          row: 1,
          column: "age",
          check: :number,
          message: "must be less than %{number}",
          metadata: %{number: 200},
          value: 300
        }
      ]

      result = %Result{valid?: false, data: [], errors: errors}

      assert %{
               "age" => ["must be greater than 0", "must be less than 200"],
               "name" => ["is required"]
             } = Result.errors_to_map(result)
    end

    test "groups cross-column errors under nil" do
      errors = [
        %Error{
          row: 0,
          column: nil,
          check: :dates_ordered,
          message: "check failed",
          metadata: %{},
          value: nil
        }
      ]

      result = %Result{valid?: false, data: [], errors: errors}

      assert %{nil => ["check failed"]} = Result.errors_to_map(result)
    end
  end

  describe "Error.format_message/1" do
    test "interpolates metadata into message template" do
      error = %Error{
        row: 0,
        check: :number,
        message: "must be greater than %{number}",
        metadata: %{kind: :greater_than, number: 0},
        value: -1
      }

      assert "must be greater than 0" = Error.format_message(error)
    end

    test "returns message unchanged when no placeholders" do
      error = %Error{row: 0, check: :required, message: "is required", metadata: %{}, value: nil}
      assert "is required" = Error.format_message(error)
    end
  end

  describe "errors_for/2 with row option" do
    test "returns errors matching the given row index" do
      errors = [
        %Error{
          row: 0,
          column: "amount",
          check: :number,
          message: "too low",
          metadata: %{},
          value: -1
        },
        %Error{
          row: 1,
          column: "name",
          check: :length,
          message: "too short",
          metadata: %{},
          value: ""
        },
        %Error{
          row: 1,
          column: "amount",
          check: :number,
          message: "too low",
          metadata: %{},
          value: -5
        }
      ]

      result = %Result{valid?: false, data: [], errors: errors}

      assert [%Error{row: 1, column: "name"}, %Error{row: 1, column: "amount"}] =
               Result.errors_for(result, row: 1)
    end
  end
end
