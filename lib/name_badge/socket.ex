defmodule NameBadge.Socket do
  use Slipstream

  require Logger

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Slipstream
  def init(_config) do
    Logger.debug("connecting to socket, config: #{inspect(config())}")
    {:ok, connect!(config())}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.debug("Connected to socket, joining channel #{topic()}")
    {:ok, join(socket, topic())}
  end

  @impl Slipstream
  def handle_message("device_gallery", "image", %{"url" => url}, socket) do
    {:ok, %{body: image}} = Req.get(url)

    {:ok, image} = Dither.decode(image)
    {:ok, raw} = Dither.to_raw(image)

    NameBadge.Display.draw(raw)

    {:ok, socket}
  end

  defp topic, do: "device_gallery"

  defp config, do: Application.get_env(:name_badge, __MODULE__)
end
