# Used by "mix format"
locals_without_parens = [
  # Schema DSL
  column: 2,
  column: 3,
  check: 2,
  check: 3
]

[
  inputs: ["{mix,.formatter,.credo,.check,.doctor}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
