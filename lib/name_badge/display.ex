defmodule NameBadge.Display do
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def draw(image, opts \\ []) do
    GenServer.call(__MODULE__, {:draw, image, opts})
  end

  def init(_opts) do
    {:ok, eink} =
      EInk.new(EInk.Driver.UC8276,
        dc_pin: "EPD_DC",
        reset_pin: "EPD_RESET",
        busy_pin: "EPD_BUSY",
        spi_device: "spidev0.0"
      )

    EInk.clear(eink, :white)
    EInk.draw(eink, initial_frame())

    Process.sleep(5_000)

    {:ok, %{eink: eink}}
  end

  def handle_call({:draw, image, opts}, _from, state) do
    img_packed = pack_bits(image)
    EInk.draw(state.eink, img_packed, opts)

    {:reply, :ok, state}
  end

  def initial_frame() do
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
  end

  def pack_bits(""), do: ""

  def pack_bits(binary) do
    for <<b0, b1, b2, b3, b4, b5, b6, b7 <- binary>>, into: <<>> do
      <<threshold(b0)::1, threshold(b1)::1, threshold(b2)::1, threshold(b3)::1,
        threshold(b4)::1, threshold(b5)::1, threshold(b6)::1, threshold(b7)::1>>
    end
  end

  defp threshold(b) when b >= 100, do: 1
  defp threshold(b) when b < 100, do: 0
end
