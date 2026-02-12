defmodule NameBadge.BatteryMock do
  use GenServer

  @voltage 5.0

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: NameBadge.Battery)
  end

  def voltage(), do: GenServer.call(NameBadge.Battery, :get_voltage)

  def charging?() do
    # Mock device is always charging (voltage > 4.5V)
    voltage() > 4.5
  end

  def percentage() do
    # Convert voltage to battery percentage
    # Typical Li-ion battery range: 3.0V (0%) to 4.2V (100%)
    v = voltage()
    min_voltage = 3.0
    max_voltage = 4.2

    percentage = ((v - min_voltage) / (max_voltage - min_voltage) * 100)
    |> max(0)
    |> min(100)
    |> round()

    percentage
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call(:get_voltage, _from, state) do
    {:reply, @voltage, state}
  end
end
