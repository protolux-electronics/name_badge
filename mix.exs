defmodule NameBadge.MixProject do
  use Mix.Project

  @app :name_badge
  @name "goatmire"
  @version "0.3.1"
  @all_targets [:trellis]

  def project do
    [
      name: @name,
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
      extra_applications: [:logger, :runtime_tools, :eex],
      mod: {NameBadge.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for :host target
      {:phoenix_playground, "~> 0.1.8", targets: [:host]},

      # Dependencies for all targets
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},
      {:slipstream, "~> 1.2"},
      {:req, "~> 0.5"},
      {:dither, "~> 0.1.1"},
      {:typst, "~> 0.1.7"},
      {:qr_code, "~> 3.2.0"},
      {:tzdata, "~> 1.1"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.0"},

      # Dependencies for all targets except :host
      {:nerves_hub_link, "~> 2.9", targets: @all_targets},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:circuits_spi, "~> 2.0", targets: @all_targets},
      {:circuits_gpio, "~> 2.1.3", targets: @all_targets},
      {:eink, github: "protolux-electronics/eink", targets: @all_targets},
      {:vintage_net_wizard,
       github: "nerves-networking/vintage_net_wizard", targets: @all_targets},

      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_trellis,
       github: "protolux-electronics/nerves_system_trellis",
       ref: "debug",
       runtime: false,
       targets: :trellis}
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
    product_key = System.get_env("NH_PRODUCT_KEY")
    product_secret = System.get_env("NH_PRODUCT_SECRET")

    not is_nil(product_key) and not is_nil(product_secret)
  end
end
