defmodule NameBadge.Display do
  use GenServer

  require Logger

  alias NameBadge.Layout

  @initial_frame """
  #place(center + horizon, image("images/logos.svg", width: 196pt))
  """

  @threshold 127

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def render_typst(markup, opts \\ []) do
    GenServer.call(__MODULE__, {:render_typst, markup, opts})
  end

  def render_png(png, opts \\ []) do
    GenServer.call(__MODULE__, {:render_png, png, opts})
  end

  def init(_opts) do
    {:ok, eink} =
      EInk.new(EInk.Driver.UC8276,
        dc_pin: "EPD_DC",
        reset_pin: "EPD_RESET",
        busy_pin: "EPD_BUSY",
        spi_device: "spidev0.0"
      )

    initial_screen =
      Layout.root_layout(@initial_frame)
      |> eval_template()
      |> prepare_png()

    EInk.clear(eink, :white)
    EInk.draw(eink, initial_screen)

    Process.sleep(:timer.seconds(3))

    {:ok, %{eink: eink}}
  end

  def handle_call({:render_typst, markup, opts}, _from, state) do
    eink_data =
      eval_template(markup)
      |> prepare_png()

    EInk.draw(state.eink, eink_data, opts)

    {:reply, :ok, state}
  end

  def handle_call({:render_png, png, opts}, _from, state) do
    eink_data = prepare_png(png)

    EInk.draw(state.eink, eink_data, opts)

    {:reply, :ok, state}
  end

  defp eval_template(template) do
    typst_opts = [root_dir: typst_dir(), extra_fonts: [fonts_dir()]]

    Typst.render_to_png!(template, [], typst_opts)
    |> List.first()
  end

  defp prepare_png(png) when is_binary(png) do
    Dither.decode!(png)
    |> prepare_png()
  end

  defp prepare_png(ref) when is_reference(ref) do
    ref
    |> Dither.grayscale!()
    |> Dither.to_raw!()
    |> pack_bits()
    |> Enum.join()
  end

  defp pack_bits(""), do: []

  defp pack_bits(<<b0, b1, b2, b3, b4, b5, b6, b7, rest::binary>>) do
    [
      <<threshold(b0)::1, threshold(b1)::1, threshold(b2)::1, threshold(b3)::1, threshold(b4)::1,
        threshold(b5)::1, threshold(b6)::1, threshold(b7)::1>>
      | pack_bits(rest)
    ]
  end

  defp threshold(b) when b >= @threshold, do: 1
  defp threshold(b) when b < @threshold, do: 0

  defp typst_dir, do: Application.app_dir(:name_badge, "priv/typst")
  defp fonts_dir, do: Path.join(typst_dir(), "fonts")
end
