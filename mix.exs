defmodule NameBadge.MixProject do
  use Mix.Project

  @app :name_badge
  @version "0.1.0"
  @all_targets [:trellis]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.13"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {NameBadge.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},
      {:slipstream, "~> 1.2"},
      {:req, "~> 0.5"},
      {:dither, github: "protolux-electronics/dither"},
      {:typst, github: "gworkman/typst"},
      {:qr_code, "~> 3.2.0"},
      {:tzdata, "~> 1.1"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.0"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:circuits_spi, "~> 2.0", targets: @all_targets},
      {:circuits_gpio, "~> 2.0", targets: @all_targets},
      {:eink, github: "protolux-electronics/eink", targets: @all_targets},

      # nerves hub
      {:nerves_hub_link, "~> 2.8", targets: @all_targets, runtime: nerves_hub_configured?()},

      # PubSub Event broadcasting
      {:phoenix_pubsub, "~> 2.1.3"},

      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_trellis,
       github: "protolux-electronics/nerves_system_trellis", runtime: false, targets: :trellis}
    ]
  end

  def release do
    [
      overwrite: true,
      # Erlang distribution is not started automatically.
      # See https://hexdocs.pm/nerves_pack/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  def nerves_hub_configured?() do
    Application.get_env(:nerves_hub_link, :host) != nil
  end
end
