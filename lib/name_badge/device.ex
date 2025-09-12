defmodule NameBadge.Device do
  @moduledoc """
  Controls navigation and rendering of screens.
  """

  use GenServer

  require Logger

  alias NameBadge.Renderer
  alias NameBadge.Screen

  def init(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def render(screen, render_type \\ :full) do
    GenServer.cast(__MODULE__, {:render, screen, render_type})
  end

  def re_render(render_type) do
    GenServer.cast(__MODULE__, {:re_render, render_type})
  end

  def navigate_back() do
    GenServer.call(__MODULE__, {:navigate, :back})
  end

  def navigate(module, params) do
    GenServer.call(__MODULE__, {:navigate, module, params})
  end

  def send_button_pressed(button, value) do
    GenServer.cast(__MODULE__, {:button_pressed, button, value})
  end

  # Callbacks

  def start_link(_args) do
    {:ok, initial_screen} = Screen.TopLevel.init(%{})

    state = %{
      stack: [initial_screen],
      current_screen: initial_screen
    }

    {:ok, state}
  end

  def handle_cast({:render, screen, render_type}, state) do
    do_render(screen, render_type)
    {:noreply, state}
  end

  def handle_cast({:re_render, render_type}, state) do
    do_render(state.current_screen, render_type)
    {:noreply, state}
  end

  def handle_cast({:button_pressed, button, value}, state) do
    state.current_screen.send_button_pressed(button, value)
    {:noreply, state}
  end

  def handle_call({:navigate, :back}, state) do
    [prev_screen | rest] = state.stack
    state = %{stack: rest, current_screen: prev_screen}

    # TODO: Figure out how to re-init the previous screen or delete the back navigation altogether.
    :ok = do_render(prev_screen, :full)

    {:reply, :ok, state}
  end

  def handle_call({:navigate, screen, params}, state) do
    new_stack = [state.current_screen | state.stack]

    # TODO: Think about if and how to terminate the previous screen.

    {:ok, _pid} = screen.module.init(params)
    :ok = do_render(screen, :full)

    state = %{stack: new_stack, current_screen: screen}

    {:reply, :ok, state}
  end

  defp do_render(screen, render_type) do
    with {:error, error} <- Renderer.render(render_type, screen) do
      Logger.error(
        "Could not render screen. Error: #{error}. Render Type: #{render_type}. Screen: #{inspect(screen)}"
      )
    end

    :ok
  end
end
