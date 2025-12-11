defmodule NameBadge.Screen.Settings.WiFi do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(_assigns) do
    """
    #pad(x: 16pt)[
      #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)
      
      = WiFi Setup

      1. Connect to wifi network #{VintageNetWizard.APMode.ssid()}
      2. Go to http://wifi.config
      3. Enter network credentials
      4. Apply configuration
      5. Long-press B to connect
    ]
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    VintageNetWizard.run_wizard()
    {:ok, screen}
  end

  @impl NameBadge.Screen
  def terminate(_reason, screen) do
    VintageNetWizard.stop_wizard()
    screen
  end
end
