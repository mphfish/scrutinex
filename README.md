# Scrutinex

[![CI](https://github.com/mphfish/scrutinex/actions/workflows/ci.yml/badge.svg)](https://github.com/mphfish/scrutinex/actions/workflows/ci.yml)

Declarative validation for tabular data in Elixir.

Define schemas with an Ecto-style DSL, then validate lists of maps from CSVs, APIs, or any other source — with type coercion, built-in checks, regex column matching, and cross-column validation.

## Installation

```elixir
def deps do
  [{:scrutinex, "~> 0.1.0"}]
end
```

## Example

```elixir
defmodule OrderSchema do
  use Scrutinex.Schema, strict: true

  column "id",       :integer, coerce: true
  column "customer", :string,  checks: [length: [min: 1]]
  column "amount",   :float,   coerce: true, checks: [number: [greater_than: 0]]
  column "status",   :string,  checks: [inclusion: ["pending", "shipped", "delivered"]]

  check :amount_valid do
    fn row -> row["amount"] > 0 or row["status"] == "pending" end
  end
end

result = Scrutinex.validate(data, OrderSchema)
result.valid?  #=> true
result.data    #=> [%{"id" => 1, "amount" => 99.99, ...}, ...]
result.errors  #=> []
```

## Features

- **Ecto-style DSL** — `column` and `check` macros with compile-time validation
- **Type coercion** — cast strings to integers, floats, booleans, dates, datetimes
- **Built-in checks** — number ranges, inclusion/exclusion, format, length, custom functions
- **Regex columns** — `column ~r/sales_.*/, :float` matches all columns by pattern
- **Cross-column checks** — validate relationships between columns
- **Strict mode** — reject undeclared columns
- **Zero runtime dependencies**

## Formatter

Add to your `.formatter.exs` for parens-free DSL:

```elixir
[
  import_deps: [:scrutinex]
]
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/scrutinex).

## License

MIT — see [LICENSE](LICENSE).
