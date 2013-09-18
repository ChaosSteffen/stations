defmodule Stations.Mixfile do
  use Mix.Project

  def project do
    [ app: :stations,
      version: "0.0.1",
      dynamos: [Stations.Dynamo],
      compilers: [:elixir, :dynamo, :app],
      env: [prod: [compile_path: "ebin"]],
      compile_path: "tmp/#{Mix.env}/stations/ebin",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [ applications: [:cowboy, :dynamo],
      mod: { Stations, [] } ]
  end

  defp deps do
    [ { :cowboy, github: "extend/cowboy" },
      { :dynamo, "0.1.0-dev", github: "elixir-lang/dynamo" },
      { :gru, github: "BananaLtd/gru" } ]
  end
end
