# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Scrutinex is an Elixir library for declarative validation of tabular data (lists of maps). It provides an Ecto-style macro DSL for defining schemas with type checking, coercion, built-in checks, regex column matching, cross-column validation, and strict mode.

## Common Commands

```bash
# Run all tests
mix test

# Run a single test file
mix test test/scrutinex/validator_test.exs

# Run a specific test by line number
mix test test/scrutinex/validator_test.exs:42

# Compile with warnings as errors
mix compile --warnings-as-errors

# Lint with Credo
mix credo --strict

# Test coverage (minimum 90%)
mix coveralls --minimum-coverage 90

# Static analysis (Dialyzer via Assay)
mix assay

# Run all checks (compile, credo, coveralls, dialyzer)
mix check
```

## Architecture

### Validation Pipeline (`Scrutinex.Validator`)

`Scrutinex.validate/2` runs this pipeline per cell in order:
1. **Null check** — reject nil/empty, or skip remaining checks if `nullable: true`
2. **Coercion** — cast strings to declared type if `coerce: true`
3. **Type check** — verify type if `coerce: false`
4. **Column checks** — run checks in declaration order, short-circuit on first failure

After all rows: cross-column checks run on coerced data.

### Schema DSL (`Scrutinex.Schema`)

Uses compile-time module attributes (`@scrutinex_columns`, `@scrutinex_checks`, `@scrutinex_strict`) accumulated via `column/3` and `check/2` macros. `__before_compile__` validates types/checks at compile time and generates a `__schema__/0` function returning a `Schema.Definition` struct.

Regex column names (e.g., `~r/sales_.*/`) are resolved at validation time against actual data keys in `Validator.resolve_columns/2`.

### Key Modules

- `Scrutinex` — public API: `validate/2`, `validate!/2`
- `Scrutinex.Schema` — macro DSL, compile-time validation
- `Scrutinex.Schema.Definition` — struct holding columns, checks, strict flag
- `Scrutinex.Validator` — core pipeline orchestration
- `Scrutinex.Coercion` — type casting and type checking
- `Scrutinex.Column` — column definition struct
- `Scrutinex.Check` — cross-column check struct (name, message, function)
- `Scrutinex.Error` — error struct with row/column/check/message/metadata/value; has `format_message/1` for interpolation
- `Scrutinex.Result` — result struct with `valid?`, `data`, `errors`; has `errors_for/2` and `errors_to_map/1`
- `Scrutinex.Checks.*` — individual check modules (Number, Inclusion, Exclusion, Format, Length, Custom)

### Error Format

Errors use Ecto-style message templates with metadata for i18n: `"must be greater than %{number}"` with `metadata: %{kind: :greater_than, number: 0}`. Use `Error.format_message/1` to interpolate.

## Dependencies

Zero runtime dependencies. Dev/test only: ex_check, credo, excoveralls, assay (dialyzer), ex_doc.
