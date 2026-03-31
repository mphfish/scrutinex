defmodule ScrutinexTest do
  use ExUnit.Case, async: true

  alias Scrutinex.Result

  defmodule OrderSchema do
    use Scrutinex.Schema, strict: true

    column("id", :integer, required: true, coerce: true)
    column("customer", :string, required: true, checks: [length: [min: 1]])

    column("amount", :float,
      coerce: true,
      checks: [number: [greater_than: 0, less_than_or_equal_to: 1_000_000]]
    )

    column("status", :string, checks: [inclusion: ["pending", "shipped", "delivered"]])

    column("tracking_id", :string,
      nullable: true,
      checks: [format: ~r/^[A-Z]{2}\d{9}[A-Z]{2}$/]
    )

    check :id_positive do
      fn row -> is_nil(row["id"]) or row["id"] > 0 end
    end
  end

  defmodule SalesSchema do
    use Scrutinex.Schema

    column("region", :string, required: true)

    column(~r/sales_.*/, :float,
      coerce: true,
      checks: [number: [greater_than_or_equal_to: 0, less_than_or_equal_to: 100]]
    )
  end

  describe "full validation with OrderSchema" do
    test "valid data passes" do
      data = [
        %{
          "id" => "1",
          "customer" => "Alice",
          "amount" => "99.99",
          "status" => "pending",
          "tracking_id" => nil
        },
        %{
          "id" => "2",
          "customer" => "Bob",
          "amount" => "150.0",
          "status" => "shipped",
          "tracking_id" => "AB123456789CD"
        }
      ]

      result = Scrutinex.validate(data, OrderSchema)
      assert result.valid?
      assert [%{"id" => 1, "amount" => 99.99}, %{"id" => 2, "amount" => 150.0}] = result.data
    end

    test "multiple errors across rows" do
      data = [
        %{
          "id" => "abc",
          "customer" => "",
          "amount" => "-5",
          "status" => "deleted",
          "tracking_id" => "bad"
        },
        %{
          "id" => "2",
          "customer" => "Bob",
          "amount" => "100.0",
          "status" => "pending",
          "tracking_id" => nil
        }
      ]

      result = Scrutinex.validate(data, OrderSchema)
      refute result.valid?

      row0_errors = Result.errors_for(result, row: 0)
      assert length(row0_errors) >= 3

      row1_errors = Result.errors_for(result, row: 1)
      assert row1_errors == []
    end

    test "strict mode rejects extra columns" do
      data = [
        %{
          "id" => "1",
          "customer" => "Alice",
          "amount" => "10.0",
          "status" => "pending",
          "tracking_id" => nil,
          "extra" => "oops"
        }
      ]

      result = Scrutinex.validate(data, OrderSchema)
      refute result.valid?

      extra_error = Enum.find(result.errors, &(&1.check == :unexpected_column))
      assert extra_error.column == "extra"
    end
  end

  describe "runtime input guards" do
    test "raises ArgumentError when data is not a list of maps" do
      assert_raise ArgumentError, ~r/expected a list of maps/, fn ->
        Scrutinex.validate(["not", "maps"], OrderSchema)
      end
    end

    test "raises ArgumentError when data is not a list" do
      assert_raise ArgumentError, ~r/expected a list of maps as first argument/, fn ->
        Scrutinex.validate("not a list", OrderSchema)
      end
    end

    test "accepts empty list" do
      result = Scrutinex.validate([], OrderSchema)
      assert result.valid?
    end
  end

  describe "validate!/2" do
    test "returns coerced data on success" do
      data = [
        %{
          "id" => "1",
          "customer" => "Alice",
          "amount" => "10.0",
          "status" => "pending",
          "tracking_id" => nil
        }
      ]

      result = Scrutinex.validate!(data, OrderSchema)
      assert [%{"id" => 1}] = result
    end

    test "raises ValidationError on failure" do
      data = [
        %{
          "id" => "abc",
          "customer" => "",
          "amount" => "-5",
          "status" => "deleted",
          "tracking_id" => "bad"
        }
      ]

      error =
        assert_raise Scrutinex.ValidationError, fn ->
          Scrutinex.validate!(data, OrderSchema)
        end

      assert error.message =~ "validation failed"
      refute error.result.valid?
    end
  end

  describe "regex column schema" do
    test "validates regex-matched columns" do
      data = [
        %{"region" => "East", "sales_q1" => "25.0", "sales_q2" => "50.0"},
        %{"region" => "West", "sales_q1" => "110.0", "sales_q2" => "30.0"}
      ]

      result = Scrutinex.validate(data, SalesSchema)
      refute result.valid?

      error = Enum.find(result.errors, &(&1.column == "sales_q1" and &1.row == 1))
      assert error.check == :number
    end
  end
end
