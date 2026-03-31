[
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs"},
    {:ex_coveralls, command: "mix coveralls"},
    {:dialyzer, false},
    {:assay, command: "mix assay"}
  ]
]
