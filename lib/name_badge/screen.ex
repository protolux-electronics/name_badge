defmodule NameBadge.Screen do
  defstruct [:action, :module, assigns: %{}]

  @type t() :: %__MODULE__{}

  @callback init(args :: any(), screen :: t()) :: {:ok, map()}
  @callback render(assigns :: map()) :: String.t()
  @callback handle_button(button_name :: String.t(), value :: integer(), state :: map()) ::
              {:noreply, map()}

  defmacro __using__(_opts) do
    quote do
      @behaviour NameBadge.Screen

      import NameBadge.Screen
    end
  end

  def assign(%__MODULE__{} = screen, key, value),
    do: %{screen | assigns: Map.put(screen.assigns, key, value)}

  def assign(%__MODULE__{} = screen, assigns) when is_map(assigns) do
    assigns = Map.merge(screen.assigns, assigns)
    %{screen | assigns: assigns}
  end

  def assign(%__MODULE__{} = screen, assigns) when is_list(assigns) do
    assign(screen, Map.new(assigns))
  end

  def navigate(%__MODULE__{} = screen, :back), do: Map.put(screen, :action, :back)

  def navigate(%__MODULE__{} = screen, module, params \\ []),
    do: Map.put(screen, :action, {:navigate, module, params})
end
