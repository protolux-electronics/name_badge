defmodule NameBadge.Screen do
  defstruct [:module, assigns: %{}]

  alias __MODULE__

  @type t() :: %__MODULE__{}

  @callback mount(params :: list(), screen :: t()) :: {:ok, t()}
  @callback render(assigns :: map()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour NameBadge.Screen

      use GenServer

      def init(params) do
        screen = %NameBadge.Screen{module: __MODULE__, assigns: %{}}
        {:ok, screen} = __MODULE__.mount(params, screen)

        GenServer.start_link(__MODULE__, screen, name: __MODULE__)
      end

      def start_link(screen) do
        {:ok, screen}
      end

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
