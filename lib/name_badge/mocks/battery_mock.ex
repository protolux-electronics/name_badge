defmodule NameBadge.BatteryMock do
  use GenServer

  @voltage_mock 5.0

  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: NameBadge.Battery)

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call(:get_voltage, _from, state) do
    {:reply, @voltage_mock, state}
  end
end
