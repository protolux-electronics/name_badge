defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  alias NameBadge.Screen

  @base_screens [
    {Screen.NameBadge, "Name Badge"},
    {Screen.Gallery, "Gallery"},
    {Screen.Snake, "Snake"},
    {Screen.Counter, "Counter"},
    {Screen.Goatmire, "Goatmire"},
    {Screen.Stats, "Stats"},
    {Screen.Weather, "Weather"},
    {Screen.Settings, "Device Settings"}
  ]

  defp screens do
    if NameBadge.CalendarService.enabled?() do
      # Insert Calendar just before Weather
      weather_index = Enum.find_index(@base_screens, &match?({Screen.Weather, _}, &1))
      List.insert_at(@base_screens, weather_index, {Screen.Calendar, "Calendar"})
    else
      @base_screens
    end
  end

  @impl NameBadge.Screen
  def render(assigns) do
    {_module, text_to_display} = Enum.at(assigns.screens, assigns.current_index)

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
          {module, _text_to_display} =
            Enum.at(screen.assigns.screens, screen.assigns.current_index)

          navigate(screen, module)
      end

    {:noreply, screen}
  end
end
