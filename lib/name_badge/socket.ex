defmodule NameBadge.Socket do
  use Slipstream

  require Logger

  def join_gallery(), do: GenServer.call(__MODULE__, :join_gallery)
  def join_config(), do: GenServer.call(__MODULE__, :join_config)

  def leave_gallery(), do: GenServer.call(__MODULE__, :leave_gallery)
  def leave_config(), do: GenServer.call(__MODULE__, :leave_config)

  def connected?(), do: GenServer.call(__MODULE__, :connected?)

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Slipstream
  def init(_config) do
    {:ok, connect!(config())}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.debug("Socket was connected")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message("device_gallery", "image", %{"url" => url}, socket) do
    {:ok, %{body: image}} = Req.get(url)

    {:ok, image} = Dither.decode(image)
    {:ok, raw} = Dither.to_raw(image)

    NameBadge.Display.draw(raw)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_call(:join_gallery, _from, socket) do
    {:reply, :ok, join(socket, "device_gallery")}
  end

  @impl Slipstream
  def handle_call(:join_config, _from, socket) do
    {:reply, :ok, join(socket, "config:" <> Nerves.Runtime.serial_number())}
  end

  @impl Slipstream
  def handle_call(:leave_gallery, _from, socket) do
    {:reply, :ok, leave(socket, "device_gallery")}
  end

  @impl Slipstream
  def handle_call(:leave_config, _from, socket) do
    {:reply, :ok, leave(socket, "config:" <> Nerves.Runtime.serial_number())}
  end

  @impl Slipstream
  def handle_call(:connected?, _from, socket), do: {:reply, connected?(socket), socket}

  defp config, do: Application.get_env(:name_badge, __MODULE__)
end
