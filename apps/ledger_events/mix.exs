defmodule LedgerEvents.MixProject do
  use Mix.Project

  def project do
    [
      app: :ledger_events,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Os ramos de nack/timeout de confirm dependem do broker recusar mensagens e
      # não são reproduzíveis de forma determinística; por isso o limite é 85%.
      # Rode com RABBITMQ_URL definido para incluir os testes de integração.
      test_coverage: [ignore_modules: [LedgerEvents.Application], summary: [threshold: 85]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {LedgerEvents.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ledger, in_umbrella: true},
      {:amqp, "~> 4.3"},
      {:broadway, "~> 1.3"},
      {:broadway_rabbitmq, "~> 0.8.2"},
      {:jason, "~> 1.2"}
    ]
  end
end
