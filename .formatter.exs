# Used by "mix format"
[
  plugins: [Breeze.HTMLFormatter],
  import_deps: [:breeze],
  locals_without_parens: [attr: 2, attr: 3],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,examples}/**/*.{ex,exs}"]
]
