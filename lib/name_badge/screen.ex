defmodule NameBadge.Screen do
  defstruct [:module, assigns: %{}]

  alias __MODULE__

  @type t() :: %__MODULE__{}

  @callback mount(params :: map(), screen :: t()) :: {:ok, t()}
  @callback render(assigns :: map()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour NameBadge.Screen

      use GenServer

      alias NameBadge.Device

      def start_link(params) do
        GenServer.start_link(__MODULE__, params, name: __MODULE__)
      end

      def send_button_pressed(button, value) do
        GenServer.cast(__MODULE__, {:button_pressed, button, value})
      end

      def get_screen() do
        GenServer.call(__MODULE__, :get_screen)
      end

      # Callbacks

      def init(params) do
        screen = %NameBadge.Screen{module: __MODULE__, assigns: %{}}
        __MODULE__.mount(params, screen)
      end

      def handle_call(:get_screen, _from, screen) do
        {:reply, screen, screen}
      end

      def handle_cast({:button_pressed, button, value}, screen) do
        {:ok, screen} = handle_button(button, value, screen)
        {:noreply, screen}
      end

      def handle_button(_button, _value, screen) do
        {:ok, screen}
      end

      defoverridable handle_button: 3

      import NameBadge.Screen
    end
  end

  def assign(%Screen{} = screen, key, value) do
    %{screen | assigns: Map.put(screen.assigns, key, value)}
  end

  def assign(%Screen{} = screen, assigns) when is_list(assigns) do
    assign(screen, Map.new(assigns))
  end

  def assign(%Screen{} = screen, assigns) when is_map(assigns) do
    assigns = Map.merge(screen.assigns, assigns)
    %{screen | assigns: assigns}
  end
end
