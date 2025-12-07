defmodule NameBadge.Screen.Settings do
  use NameBadge.Screen

  alias NameBadge.Screen.Settings

  @settings [
    {"Personalization", Settings.QrCode},
    {"WiFi Settings", Settings.WiFi},
    {"Tutorial", Settings.Tutorial},
    {"Sudo Mode", Settings.SudoMode}
  ]

  @impl NameBadge.Screen
  def render(assigns) do
    """
    #set text(size: 24pt)
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)

    = Device Settings

    #v(16pt)

    #{render_settings(assigns.settings, assigns.current_index)}
    """
  end

  def render_settings(settings, current_index) do
    table_items =
      for {{text, _action}, index} <- Enum.with_index(settings) do
        "#{if index == current_index, do: arrow(), else: "[]"}, [#{text}]"
      end
      |> Enum.join(", ")

    """
    #grid(columns: (auto, 1fr), column-gutter: 8pt, row-gutter: 12pt, #{table_items})
    """
  end

  def arrow do
    """
    align(left + horizon)[
      #image(\"images/arrow.svg\", height: 12pt)
    ]
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    screen =
      screen
      |> assign(button_hints: %{a: "Scroll", b: "Select"})
      |> assign(settings: @settings, current_index: 0)

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, _press_type, screen) do
    num_settings = length(screen.assigns.settings)
    screen = assign(screen, current_index: rem(screen.assigns.current_index + 1, num_settings))

    {:noreply, screen}
  end

  def handle_button(:button_2, _press_type, screen) do
    {_text, module} = Enum.at(screen.assigns.settings, screen.assigns.current_index)

    {:noreply, navigate(screen, module)}
  end
end
