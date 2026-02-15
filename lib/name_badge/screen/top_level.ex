defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  alias NameBadge.Screen

  @base_screens [
    {Screen.NameBadge, "Name Badge"},
    {Screen.Gallery, "Gallery"},
    {Screen.Snake, "Snake"},
    {Screen.Weather, "Weather"},
    {Screen.Settings, "Device Settings"}
  ]

  defp screens do
    if NameBadge.CalendarService.enabled?() do
      # Insert Calendar after Weather
      List.insert_at(@base_screens, 4, {Screen.Calendar, "Calendar"})
    else
      @base_screens
    end
  end

  @impl NameBadge.Screen
  def render(assigns) do
    text_to_display = screen_text(Enum.at(assigns.screens, assigns.current_index))

    """
    #place(center + horizon, text(size: 64pt, font: "Silkscreen", tracking: -8pt, "#{text_to_display}"))
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    screen =
      screen
      |> assign(screens: screens(), current_index: 0)
      |> assign(button_hints: %{a: "Next", b: "Select"})

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
          entry = Enum.at(screen.assigns.screens, screen.assigns.current_index)
          navigate_to_screen(screen, entry)
      end

    {:noreply, screen}
  end

  defp screen_text({_module, text}), do: text
  defp screen_text({_module, text, _args}), do: text

  defp navigate_to_screen(screen, {module, _text}), do: navigate(screen, module)
  defp navigate_to_screen(screen, {module, _text, args}), do: navigate(screen, module, args)
end
