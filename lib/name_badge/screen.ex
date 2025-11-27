defmodule NameBadge.Screen do
  use GenServer

  @type t :: %__MODULE__{module: atom(), assigns: map(), action: nil | tuple(), mount_args: any()}

  defstruct [:module, assigns: %{}, action: nil, mount_args: nil]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def render(pid, timeout \\ 1000) do
    GenServer.call(pid, :render, timeout)
  end

  def assign(screen, key, value) do
    %{screen | assigns: Map.put(screen.assigns, key, value)}
  end

  def assign(screen, keyword) do
    new_assigns = Map.new(keyword)
    %{screen | assigns: Map.merge(screen.assigns, new_assigns)}
  end

  def handle_button(pid, which_button, press_type, timeout \\ 1000) do
    GenServer.call(pid, {:handle_button, which_button, press_type}, timeout)
  end

  @impl true
  def init(args) do
    {screen_args, mount_args} = Keyword.split(args, [:module])
    module = Keyword.fetch!(screen_args, :module)

    {:ok, %__MODULE__{module: module, mount_args: mount_args}, {:continue, :mount}}
  end

  @impl GenServer
  def handle_continue(:mount, screen) do
    {:ok, screen} = screen.module.mount(screen.mount_args, screen)
    {:noreply, screen}
  end

  @impl GenServer
  def handle_call(:render, _from, screen) do
    markup = screen.module.render(screen.assigns)
    {:reply, markup, screen}
  end

  def handle_call({:handle_button, button, press}, _from, screen) do
    screen = screen.module.handle_button(button, press, screen)
    {:reply, :ok, screen}
  end

  ###################### CALLBACK ######################

  defmacro __using__(_opts) do
    quote do
      @behaviour NameBadge.Screen
      import NameBadge.Screen, only: [assign: 2, assign: 3]

      # default mount
      def mount(args, screen), do: {:ok, screen}

      # default render
      def render(assigns) do
        """
        #place(center + horizon, text(size: 64pt)[#{inspect(__MODULE__)}])
        """
      end

      # default handle_button
      # NOTE: handle_button doesn't return {:noreply, screen} like LiveView!
      def handle_button(_button, _press, screen), do: screen

      defoverridable NameBadge.Screen
    end
  end

  @callback mount(keyword(), t()) :: {:ok, t()}
  @callback render(map()) :: String.t()
  @callback handle_button(atom(), :single_press | :long_press, t()) :: t()
end
