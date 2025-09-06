defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  require Logger

  @screens [
    {"Name Badge", NameBadge.Screen.NameBadge},
    {"Gallery", NameBadge.Screen.Gallery},
    {"Schedule", NameBadge.Screen.Schedule},
    {"Settings", NameBadge.Screen.Settings}
  ]

  def render(assigns) do
    """
    #place(center + horizon, text(size: 72pt, font: "Silkscreen", tracking: -8pt, "#{assigns.current_screen_name}"))
    """
  end

  def init(_opts) do
    {name, _module} = Enum.at(@screens, 0)

    {:ok,
     %{
       screen_index: 0,
       screens: @screens,
       current_screen_name: name,
       button_hints: %{a: "Next page", b: "Select page"}
     }}
  end

  def handle_button("BTN_1", 0, screen) do
    new_index = rem(screen.assigns.screen_index + 1, length(@screens))
    {name, _module} = Enum.at(@screens, new_index)

    screen =
      screen
      |> assign(:screen_index, new_index)
      |> assign(:current_screen_name, name)

    {:render, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    {_name, module} = Enum.at(@screens, screen.assigns.screen_index)

    {:render, navigate(screen, module)}
  end

  def handle_button(button_name, value, screen) do
    Logger.info("Button handler! #{button_name}, #{value}")
    {:norender, screen}
  end
end
