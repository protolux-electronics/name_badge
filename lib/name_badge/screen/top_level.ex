defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  alias NameBadge.Screen

  @screens [
    {Screen.NameBadge, "Name Badge 1"},
    {Screen.NameBadge, "Name Badge 2"},
    {Screen.NameBadge, "Name Badge 3"},
    {Screen.NameBadge, "Name Badge 4"}
  ]

  @impl NameBadge.Screen
  def render(assigns) do
    {_module, text_to_display} = Enum.at(assigns.screens, assigns.current_index)

    """
    #place(center + horizon, text(size: 64pt, font: "Silkscreen", tracking: -8pt, "#{text_to_display}"))
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    screen = assign(screen, screens: @screens, current_index: 0)

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(button, _press, screen) do
    screen =
      case button do
        :button_1 ->
          num_screens = length(screen.assigns.screens)
          assign(screen, current_index: rem(screen.assigns.current_index + 1, num_screens))

        :button_2 ->
          {module, _text_to_display} =
            Enum.at(screen.assigns.screens, screen.assigns.current_index)

          navigate(screen, module)
      end

    {:noreply, screen}
  end
end
