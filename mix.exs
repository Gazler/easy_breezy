defmodule EasyBreezy.MixProject do
  use Mix.Project

  def project do
    [
      app: :easy_breezy,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {EasyBreezy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:breeze, github: "gazler/breeze"},
      {:file_system, "~> 1.1", optional: true, runtime: Mix.env() == :dev},
      {:lumis, "~> 0.5.0"}
    ]
  end
end
