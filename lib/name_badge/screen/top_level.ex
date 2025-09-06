defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  require Logger

  @screens %{
    "Name Badge" => NameBadge.Screen.NameBadge,
    "Gallery" => NameBadge.Screen.Gallery,
    "Schedule" => NameBadge.Screen.Schedule,
    "Settings" => NameBadge.Screen.Settings
  }

  @screen_names ["Name Badge", "Gallery", "Schedule", "Settings"]

  def render(assigns) do
    """
    #place(center + horizon, text(size: 72pt, font: "Silkscreen", tracking: -8pt, "#{Enum.at(assigns.screens, assigns.screen_index)}"))
    """
  end

  def init(_opts) do
    {:ok, %{screen_index: 0, screens: @screen_names}}
  end

  def handle_button("BTN_1", 1, screen) do
    new_index = rem(screen.assigns.screen_index + 1, length(@screen_names))

    {:render, assign(screen, :screen_index, new_index)}
  end

  def handle_button(button_name, value, screen) do
    Logger.info("Button handler! #{button_name}, #{value}")
    {:norender, screen}
  end
end
