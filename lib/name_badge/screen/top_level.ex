defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  require Logger

  @screens [
    {"Name Badge", NameBadge.Screen.NameBadge},
    {"Gallery", NameBadge.Screen.Gallery},
    {"Snake", NameBadge.Screen.Snake},
    {"Schedule", NameBadge.Screen.Schedule},
    {"Settings", NameBadge.Screen.Settings}
  ]

  def render(assigns) do
    """
    #place(center + horizon, text(size: 72pt, font: "Silkscreen", tracking: -8pt, "#{assigns.current_screen_name}"))
    """
  end

  def mount(_params, screen) do
    {name, _module} = Enum.at(@screens, 0)

    screen =
      screen
      |> assign(:screen_index, 0)
      |> assign(:screens, @screens)
      |> assign(:current_screen_name, name)
      |> assign(:button_hints, %{a: "Next Page", b: "Select"})

    {:ok, screen}
  end

  def handle_button("BTN_1", 0, screen) do
    new_index = rem(screen.assigns.screen_index + 1, length(@screens))
    {name, _module} = Enum.at(@screens, new_index)

    screen =
      screen
      |> assign(:screen_index, new_index)
      |> assign(:current_screen_name, name)

    :ok = Device.render(screen, :partial)

    {:ok, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    {_name, module} = Enum.at(@screens, screen.assigns.screen_index)

    :ok = Device.navigate(module, %{})

    {:ok, screen}
  end

  def handle_button(_button_name, _value, screen) do
    {:ok, screen}
  end
end
