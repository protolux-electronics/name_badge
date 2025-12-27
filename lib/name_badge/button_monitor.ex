defmodule NameBadge.ButtonMonitor do
  use GenServer

  alias Circuits.GPIO

  require Logger

  @long_press_timeout_default 500
  @genserver_args [:name, :timeout, :debug, :spawn_opt, :hibernate_after]
  @button_gpios [
    button_1: "BTN_1",
    button_2: "BTN_2"
  ]

  def send_button_press(which_button, press_type) do
    Registry.dispatch(NameBadge.Registry, which_button, fn pids ->
      for {pid, _value} <- pids, do: send(pid, {:button_event, which_button, press_type})
    end)
  end

  def start_link(args) do
    {genserver_args, args} = Keyword.split(args, @genserver_args)
    GenServer.start_link(__MODULE__, args, genserver_args)
  end

  def subscribe(button_name),
    do: Registry.register(NameBadge.Registry, button_name, nil)

  def unsubscribe(button_name), do: Registry.unregister(NameBadge.Registry, button_name)

  @impl GenServer
  def init(opts) do
    button_name = Keyword.fetch!(opts, :button)
    button_gpio = Keyword.fetch!(@button_gpios, button_name)
    long_press_timeout = Keyword.get(opts, :long_press_timeout, @long_press_timeout_default)

    {:ok, btn} = GPIO.open(button_gpio, :input)
    :ok = GPIO.set_interrupts(btn, :both)

    state = %{
      btn: btn,
      pressed_at: nil,
      long_press_timeout: long_press_timeout,
      name: button_name
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:circuits_gpio, _btn, _ts, 0}, state) do
    now = NaiveDateTime.utc_now()
    {:noreply, %{state | pressed_at: now}}
  end

  @impl GenServer
  def handle_info({:circuits_gpio, _btn, _ts, _value}, %{pressed_at: nil} = state) do
    # this is a startup glitch - the button is registering a "button up" event
    # but the button was never pressed down. So we just ignore it for now
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:circuits_gpio, _btn, _ts, 1}, state) do
    now = NaiveDateTime.utc_now()

    case NaiveDateTime.diff(now, state.pressed_at, :millisecond) do
      diff_duration when diff_duration < state.long_press_timeout ->
        send_button_press(state.name, :single_press)

      _ ->
        send_button_press(state.name, :long_press)
    end

    {:noreply, state}
  end
end
