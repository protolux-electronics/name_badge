defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(assigns) do
    "#place(center + horizon, text(size: 32pt)[You pressed A #{assigns.button_1} times, B #{assigns.button_2} times])"
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    screen = assign(screen, button_1: 0, button_2: 0)

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(button, _press, screen) do
    screen =
      if button == :button_1 do
        navigate(screen, NameBadge.Screen.NameBadge)
      else
        screen
      end

    {:noreply, assign(screen, button, screen.assigns[button] + 1)}
  end
end
