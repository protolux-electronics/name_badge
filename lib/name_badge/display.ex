defmodule NameBadge.Display do
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def draw(image, opts \\ []) do
    GenServer.call(__MODULE__, {:draw, image, opts})
  end

  def get_current_frame() do
    GenServer.call(__MODULE__, :get_current_frame)
  end

  def init(_opts) do
    initial_frame =
      """
      #set page(width: 400pt, height: 300pt)
      #place(center + horizon, image("images/logos.svg", width: 196pt))
      """
      |> Typst.render_to_png!([], root_dir: Application.app_dir(:name_badge, "priv/typst"))
      |> List.first()
      |> Dither.decode!()
      |> Dither.grayscale!()
      |> Dither.to_raw!()
      |> pack_bits()

    {:ok, eink} = setup_eink(initial_frame)

    {:ok, %{eink: eink}}
  end

  def handle_call({:draw, image, opts}, _from, state) do
    img_packed = pack_bits(image)
    do_draw(state, img_packed, opts)

    {:reply, :ok, Map.put(state, :current_frame, img_packed)}
  end

  @impl GenServer
  def handle_call(:get_current_frame, _from, %{current_frame: current_frame} = state) do
    {:reply, current_frame, state}
  end

  if Mix.target() == :host do
    def setup_eink(_initial_frame), do: {:ok, :noop}
  else
    def setup_eink(initial_frame) do
      {:ok, eink} =
        EInk.new(EInk.Driver.UC8276,
          dc_pin: "EPD_DC",
          reset_pin: "EPD_RESET",
          busy_pin: "EPD_BUSY",
          spi_device: "spidev0.0"
        )

      EInk.clear(eink, :white)
      EInk.draw(eink, initial_frame)

      Process.sleep(5_000)

      {:ok, eink}
    end
  end

  if Mix.target() == :host do
    defp do_draw(_state, img_packed, _opts) do
      Phoenix.PubSub.broadcast(NameBadge.PubSub, "display:frame", {:frame, img_packed})
      Process.sleep(100)
    end
  else
    defp do_draw(state, img_packed, opts) do
      EInk.draw(state.eink, img_packed, opts)
    end
  end

  defp pack_bits(""), do: ""

  defp pack_bits(binary) do
    for <<b0, b1, b2, b3, b4, b5, b6, b7 <- binary>>, into: <<>> do
      << threshold(b0)::1, threshold(b1)::1, threshold(b2)::1, threshold(b3)::1,
        threshold(b4)::1, threshold(b5)::1, threshold(b6)::1, threshold(b7)::1 >>
    end
  end

  defp threshold(b) when b >= 100, do: 1
  defp threshold(b) when b < 100, do: 0
end
