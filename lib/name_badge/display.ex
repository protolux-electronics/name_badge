defmodule NameBadge.Display do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, eink} =
      EInk.new(EInk.Driver.UC8276,
        dc_pin: "EPD_DC",
        reset_pin: "EPD_RESET",
        busy_pin: "EPD_BUSY",
        spi_device: "spidev0.0"
      )

    EInk.clear(eink, :white)

    Process.send_after(self(), :draw, 5_000)

    priv_dir = Application.app_dir(:name_badge, "priv")

    files =
      priv_dir
      |> File.ls!()
      |> Enum.map(&Path.join(priv_dir, &1))

    {:ok, %{eink: eink, index: 0, files: files}}
  end

  def handle_info(:draw, state) do
    image =
      state.files
      |> Enum.at(state.index)
      |> File.read!()

    EInk.draw(state.eink, image)

    Process.send_after(self(), :draw, 5_000)

    {:noreply, %{state | index: rem(state.index + 1, length(state.files))}}
  end

  def handle_info(:clear, state) do
    EInk.clear(state.eink, :white)

    Process.send_after(self(), :draw, 5_000)

    {:noreply, state}
  end
end
