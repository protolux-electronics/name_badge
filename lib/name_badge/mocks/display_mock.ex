defmodule NameBadge.DisplayMock do
  use GenServer

  def get_current_frame() do
    GenServer.call(NameBadge.Display, :get_current_frame)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: NameBadge.Display)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{current_frame: NameBadge.Display.initial_frame()}}
  end

  @impl GenServer
  def handle_call({:draw, image, _opts}, _from, state) do
    img_packed = NameBadge.Display.pack_bits(image)
    Phoenix.PubSub.broadcast(NameBadge.PubSub, "display:frame", {:frame, img_packed})
    Process.sleep(100)

    {:reply, :ok, Map.put(state, :current_frame, img_packed)}
  end

  @impl GenServer
  def handle_call(:get_current_frame, _from, %{current_frame: current_frame} = state) do
    {:reply, current_frame, state}
  end
end
