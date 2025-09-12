defmodule NameBadge.Buttons do
  @moduledoc """
  Handles the connect to buttons and button presses.
  """

  use GenServer

  alias Circuits.GPIO

  @btn_1 "BTN_1"
  @btn_2 "BTN_2"

  def init(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  # Callbacks

  def start_link(_args) do
    {:ok, btn_1} = GPIO.open(@btn_1, :input)
    {:ok, btn_2} = GPIO.open(@btn_2, :input)

    GPIO.set_interrupts(btn_1, :both)
    GPIO.set_interrupts(btn_2, :both)

    state = %{btn_1: btn_1, btn_2: btn_2}

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:circuits_gpio, which_button, _ts, value}, state) do
    Logger.info("button pressed: #{which_button} - #{value}")

    state.current_screen.module.handle_button(which_button, value, state.current_screen)
    |> handle_screen_result(state)

    {:noreply, state}
  end
end
