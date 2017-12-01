defmodule Ricochet.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ricochet,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Ricochet, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cowboy, git: "https://github.com/ninenines/cowboy", tag: "2.1.0"},
      {:gun, git: "https://github.com/ninenines/gun", tag: "1.0.0-pre.4"},
      {:cowlib, git: "https://github.com/ninenines/cowlib", tag: "2.0.1", override: true},
      {:ranch, git: "https://github.com/ninenines/ranch", tag: "1.4.0", override: true}
    ]
  end
end
