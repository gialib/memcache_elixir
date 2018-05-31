defmodule Memcache.Mixfile do
  use Mix.Project

  def project do
    [
      app: :memcache,
      version: "0.1.1",
      elixir: "~> 1.0",
      description: description(),
      package: package(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [applications: [:logger, :poolboy], mod: {Memcache, []}]
  end

  defp deps do
    [
      {:earmark, "~> 1.2.5", only: :dev},
      {:ex_doc, "~> 0.18.3", only: :dev},
      {:poolboy, "~> 1.5.1"},
      {:jason, "~> 1.0"},
      {:connection, "~> 1.0.4"}
    ]
  end

  defp description do
    """
    Memcache client library utilizing the memcache binary protocol.
    """
  end

  defp package do
    [
      maintainers: ["happy"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/gialib/memcache_elixir"}
    ]
  end
end
