defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(assigns) do
    "#place(center + horizon, text(size: 32pt)[You pressed #{assigns.count} times])"
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    screen = assign(screen, count: 0)

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(button, press, screen) do
    assign(screen, count: screen.assigns.count + 1)
  end
end
