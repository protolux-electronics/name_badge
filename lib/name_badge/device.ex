defmodule NameBadge.Device do
  @moduledoc """
  Controls navigation and rendering of screens.
  """

  use GenServer

  require Logger

  alias NameBadge.Renderer
  alias NameBadge.Screen

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def render(%Screen{} = screen, render_type \\ :full) do
    GenServer.cast(__MODULE__, {:render, screen, render_type})
  end

  def re_render(render_type) when render_type in [:full, :partial] do
    GenServer.cast(__MODULE__, {:re_render, render_type})
  end

  def navigate_back() do
    GenServer.cast(__MODULE__, {:navigate, :back})
  end

  def navigate(module, params) when is_map(params) do
    GenServer.cast(__MODULE__, {:navigate, module, params})
  end

  def send_button_pressed(button, value) do
    GenServer.cast(__MODULE__, {:button_pressed, button, value})
  end

  def list_alive_screens() do
    [
      Screen.Gallery,
      Screen.NameBadge,
      Screen.Schedule,
      Screen.Settings,
      Screen.Snake,
      Screen.Survey,
      Screen.TopLevel
    ]
    |> Enum.map(fn module ->
      {module, Process.whereis(module)}
    end)
  end

  # Callbacks

  def init(_opts) do
    initial_module = Screen.Startup

    initial_module.start_link(%{})

    state = %{
      stack: [initial_module],
      current_module: initial_module
    }

    {:ok, state}
  end

  def handle_cast({:render, screen, render_type}, state) do
    Logger.info("Rendering #{screen.module} with #{render_type}")
    do_render(screen, render_type)
    {:noreply, state}
  end

  def handle_cast({:re_render, render_type}, state) do
    Logger.info("Re-rendering #{state.current_module} with #{render_type}")
    screen = state.current_module.get_screen()
    do_render(screen, render_type)
    {:noreply, state}
  end

  def handle_cast({:button_pressed, button, value}, state) do
    state.current_module.send_button_pressed(button, value)
    {:noreply, state}
  end

  def handle_cast({:navigate, :back}, state) do
    [_current_module, prev_module | rest] = state.stack
    state = Map.put(state, :stack, rest)

    state = navigate_to(prev_module, %{}, state)

    {:noreply, state}
  end

  def handle_cast({:navigate, module, params}, state) do
    state = navigate_to(module, params, state)

    {:noreply, state}
  end

  defp navigate_to(module, params, state) do
    Logger.info("Navigating to #{module}. New stack: #{inspect(state.stack)}")

    # Stop the previous screen if it is different
    if module != state.current_module do
      Logger.info("Stopping screen #{state.current_module}")
      GenServer.stop(state.current_module)
    end

    # Start up the new screen
    Logger.info("Starting screen #{module}")
    module.start_link(params)
    screen = module.get_screen()
    :ok = render(screen, :full)

    Logger.info("Started and rendered new screen #{module}")

    new_stack = [module | state.stack]

    %{stack: new_stack, current_module: module}
  end

  defp do_render(%Screen{} = screen, render_type) do
    with {:error, error} <- Renderer.render(screen, render_type) do
      Logger.error(
        "Could not render screen. Error: #{error}. Render Type: #{render_type}. Screen: #{inspect(screen)}"
      )
    end

    :ok
  end
end
