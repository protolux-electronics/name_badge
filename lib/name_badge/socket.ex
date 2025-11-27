defmodule NameBadge.Socket do
  use Slipstream

  require Logger

  def join_gallery(), do: GenServer.call(__MODULE__, :join_gallery)

  def join_config(token, config \\ %{}),
    do: GenServer.call(__MODULE__, {:join_config, token, config})

  def leave_gallery(), do: GenServer.call(__MODULE__, :leave_gallery)
  def leave_config(token), do: GenServer.call(__MODULE__, {:leave_config, token})

  def connected?(), do: GenServer.call(__MODULE__, :connected?)

  def survey_response(token, response),
    do: GenServer.call(__MODULE__, {:survey_response, token, response})

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
    {:ok, join(socket, "survey")}
  end

  @impl Slipstream
  def handle_message("device_gallery", "image", %{"url" => url}, socket) do
    {:ok, %{body: image}} = Req.get(url)

    raise "TODO"

    {:ok, socket}
  end

  @impl Slipstream
  def handle_message("config:" <> _token, "apply", config, socket) do
    Logger.info("Received new configuration! #{inspect(config)}")

    NameBadge.Config.store_config(config)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_message("survey", "question", question, socket) do
    Logger.info("Received new survey! #{inspect(question)}")
    send(NameBadge.Renderer, {:survey_question, question})

    {:ok, socket}
  end

  @impl Slipstream
  def handle_call(:join_gallery, _from, socket) do
    {:reply, :ok, join(socket, "device_gallery")}
  end

  @impl Slipstream
  def handle_call({:join_config, token, config}, _from, socket) do
    {:reply, :ok, join(socket, "config:" <> token, config)}
  end

  @impl Slipstream
  def handle_call(:leave_gallery, _from, socket) do
    {:reply, :ok, leave(socket, "device_gallery")}
  end

  @impl Slipstream
  def handle_call({:leave_config, token}, _from, socket) do
    {:reply, :ok, leave(socket, "config:" <> token)}
  end

  @impl Slipstream
  def handle_call({:survey_response, token, response}, _from, socket) do
    push!(socket, "survey", "response", %{token: token, response: response})
    {:reply, :ok, socket}
  end

  @impl Slipstream
  def handle_call(:connected?, _from, socket), do: {:reply, connected?(socket), socket}

  defp config, do: [uri: "wss://#{Application.get_env(:name_badge, :base_url)}/device/websocket"]
end
