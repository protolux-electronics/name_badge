defmodule NameBadge.Screen do
  defstruct [:action, :module, assigns: %{}]

  @callback init(args :: any()) :: {:ok, map()}
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

  def navigate(%__MODULE__{} = screen, :back), do: Map.put(screen, :action, :back)

  def navigate(%__MODULE__{} = screen, module, params \\ []),
    do: Map.put(screen, :action, {:navigate, module, params})
end
