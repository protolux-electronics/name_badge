defmodule NameBadge.Screen.Settings.Tutorial do
  use NameBadge.Screen

  require Logger

  @impl NameBadge.Screen
  def render(%{welcome_screen: true}) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)

    = Welcome!

    To get started, power on the device with the switch to the left      
    """
  end

  def render(%{step: 1}) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)

    = Tutorial

    This name badge has two buttons, A and B.

    Press A to continue.
    """
  end

  @impl NameBadge.Screen
  def render(%{step: 2} = assigns) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)

    = Tutorial

    Each screen has some information about what pressing A and B will do.
    You can find that information at the bottom.

    Counter: #{assigns.counter}.
    """
  end

  @impl NameBadge.Screen
  def render(%{step: 3} = assigns) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)

    = Tutorial

    You can exit ANY screen by long-pressing the B button.
    A long press is registered after 500ms.

    To #{if assigns.tutorial_enabled, do: "disable", else: "enable"} the tutorial after boot, press the A button.
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    screen =
      screen
      |> assign(step: 1, counter: 0, tutorial_enabled: true)
      |> assign(button_hints: %{a: "Next"})

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, %{assigns: %{step: 3}} = screen) do
    new_enabled = not screen.assigns.tutorial_enabled
    enable_text = if new_enabled, do: "Disable", else: "Enable"

    show_tutorial_on_boot(new_enabled)

    screen =
      screen
      |> assign(tutorial_enabled: new_enabled)
      |> assign(button_hints: %{a: "#{enable_text} tutorial after boot"})

    {:noreply, screen}
  end

  def handle_button(:button_1, :long_press, screen) do
    {:noreply, assign(screen, welcome_screen: true, button_hints: %{})}
  end

  def handle_button(:button_1, :single_press, screen) do
    new_step = min(screen.assigns.step + 1, 3)

    screen =
      case new_step do
        2 -> assign(screen, counter: 0, button_hints: %{a: "Next", b: "Increment counter"})
        3 -> assign(screen, button_hints: %{a: "Disable tutorial after boot"})
      end
      |> assign(step: new_step)

    {:noreply, screen}
  end

  def handle_button(:button_2, :single_press, screen) do
    screen =
      case screen.assigns.step do
        2 -> assign(screen, counter: screen.assigns.counter + 1)
        _ -> screen
      end

    {:noreply, screen}
  end

  defp show_tutorial_on_boot(show) do
    config = NameBadge.Config.load_config()

    updated_config = Map.put(config, "show_tutorial", show)

    Logger.info("updated config! #{inspect(updated_config)}")

    NameBadge.Config.store_config(updated_config)
  end
end
