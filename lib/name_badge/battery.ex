defmodule NameBadge.Battery do
  use GenServer

  @battery_impl Application.compile_env(:name_badge, :battery_impl)

  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)

  def voltage(), do: GenServer.call(@battery_impl, :get_voltage)

  def charging?() do
    # consider the device charging when input voltage is 4.5V or
    # greater (as required by USB spec)
    voltage() > 4.5
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, 500)
    alpha = Keyword.get(opts, :alpha, 0.9)

    timer = :timer.send_interval(interval, :update)

    {:ok, %{interval: interval, alpha: alpha, timer: timer, voltage: read_voltage()}}
  end

  @impl true
  def handle_call(:get_voltage, _from, state) do
    {:reply, state.voltage, state}
  end

  @impl true
  def handle_info(:update, state) do
    # low pass filter (exponential average)
    state =
      update_in(state.voltage, fn v ->
        v * state.alpha + read_voltage() * (1 - state.alpha)
      end)

    {:noreply, state}
  end

  defp read_voltage do
    adc_raw =
      "/sys/bus/iio/devices/iio:device0/in_voltage0_raw"
      |> File.read!()
      |> String.trim()
      |> String.to_integer()

    # adc_raw / MAX_ADC_VALUE * ADC_REFERENCE_VOLTAGE * VOLTAGE_DIVIDER
    # On the PCB, the voltage divider is 453k and 51k resistors
    # So the value for the voltage divider is (453 + 51) / 51 = 9.8823529412
    # (the units cancel in this equation)

    adc_raw / 4095.0 * 1.8 * 9.8823529412
  end
end
