defmodule NameBadge.ScreenManager do
  use GenServer

  require Logger

  alias NameBadge.Screen

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def navigate(:back) do
    GenServer.cast(__MODULE__, :back)
  end

  def navigate(module) do
    GenServer.cast(__MODULE__, {:navigate, module})
  end

  @impl GenServer
  def init(_opts) do
    initial_stack =
      cond do
        should_show_tutorial?() -> [Screen.Settings.Tutorial, Screen.TopLevel]
        true -> [Screen.TopLevel]
      end

    Logger.info("initial stack: #{inspect(initial_stack)}")

    {:ok, pid} = Screen.start_link(module: hd(initial_stack))

    {:ok, %{stack: initial_stack, current_screen: pid}}
  end

  @impl GenServer
  def handle_cast({:navigate, module}, state) do
    Screen.shutdown(state.current_screen)
    {:ok, pid} = Screen.start_link(module: module)

    new_stack = [module | state.stack]

    {:noreply, %{state | stack: new_stack, current_screen: pid}}
  end

  def handle_cast(:back, state) do
    case tl(state.stack) do
      [] ->
        {:noreply, state}

      [previous_screen | _rest] = new_stack ->
        Screen.shutdown(state.current_screen)
        {:ok, pid} = Screen.start_link(module: previous_screen)

        {:noreply, %{state | stack: new_stack, current_screen: pid}}
    end
  end

  defp should_show_tutorial?() do
    config = NameBadge.Config.load_config()

    case config do
      %{"show_tutorial" => show_tutorial} when is_boolean(show_tutorial) -> show_tutorial
      _other -> true
    end
  end
end
