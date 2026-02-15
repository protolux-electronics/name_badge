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

  def navigate(module) when is_atom(module) do
    GenServer.cast(__MODULE__, {:navigate, module, nil})
  end

  def navigate(module, mount_args) when is_atom(module) do
    GenServer.cast(__MODULE__, {:navigate, module, mount_args})
  end

  @impl GenServer
  def init(_opts) do
    initial_stack =
      cond do
        should_show_tutorial?() -> [{Screen.Settings.Tutorial, nil}, {Screen.TopLevel, nil}]
        true -> [{Screen.TopLevel, nil}]
      end

    {module, mount_args} = hd(initial_stack)
    {:ok, pid} = Screen.start_link(module: module, mount_args: mount_args)

    {:ok, %{stack: initial_stack, current_screen: pid}}
  end

  @impl GenServer
  def handle_cast({:navigate, module, mount_args}, state) do
    Screen.shutdown(state.current_screen)
    {:ok, pid} = Screen.start_link(module: module, mount_args: mount_args)

    new_stack = [{module, mount_args} | state.stack]

    {:noreply, %{state | stack: new_stack, current_screen: pid}}
  end

  def handle_cast(:back, state) do
    case tl(state.stack) do
      [] ->
        {:noreply, state}

      [{previous_module, previous_mount_args} | _rest] = new_stack ->
        Screen.shutdown(state.current_screen)
        {:ok, pid} = Screen.start_link(module: previous_module, mount_args: previous_mount_args)

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
