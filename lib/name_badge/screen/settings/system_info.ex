defmodule NameBadge.Screen.Settings.SystemInfo do
  use NameBadge.Screen

  # Define information sections for scrolling
  @sections [
    :firmware,
    :network,
    :battery
  ]

  @impl NameBadge.Screen
  def render(assigns) do
    case Enum.at(@sections, assigns.scroll_index) do
      :firmware -> render_firmware(assigns)
      :network -> render_network(assigns)
      :battery -> render_battery(assigns)
    end
  end

  defp render_firmware(assigns) do
    """
    #set text(size: 18pt)
    #show heading: set text(font: "Silkscreen", size: 28pt, weight: 400, tracking: -4pt)

    = System Info

    == Firmware (1/3)

    #v(12pt)

    *Firmware:* #{assigns.version}

    #v(12pt)

    *Elixir:* #{assigns.elixir_version}

    #v(12pt)

    *OTP:* #{assigns.otp_version}
    """
  end

  defp render_network(assigns) do
    """
    #set text(size: 18pt)
    #show heading: set text(font: "Silkscreen", size: 28pt, weight: 400, tracking: -4pt)

    = System Info

    == Network (2/3)

    #v(12pt)

    *WiFi:* #{assigns.wifi_ssid}

    #v(12pt)

    *WiFi IP:* #{assigns.wifi_ip}

    #v(12pt)

    *USB IP:* #{assigns.usb_ip}
    """
  end

  defp render_battery(assigns) do
    """
    #set text(size: 18pt)
    #show heading: set text(font: "Silkscreen", size: 28pt, weight: 400, tracking: -4pt)

    = System Info

    == Battery (3/3)

    #v(12pt)

    *Battery:* #{assigns.battery_percentage}%

    #v(12pt)

    *Status:* #{assigns.charging_status}
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    version = get_version()
    elixir_version = System.version()
    otp_version = System.otp_release()
    
    wifi_ssid = get_wifi_ssid()
    wifi_ip = get_wifi_ip()
    usb_ip = get_usb_ip()
    
    {battery_percentage, charging_status} = get_battery_info()

    screen =
      screen
      |> assign(button_hints: %{a: "Next", b: "Prev"})
      |> assign(scroll_index: 0)
      |> assign(version: version)
      |> assign(elixir_version: elixir_version)
      |> assign(otp_version: otp_version)
      |> assign(wifi_ssid: wifi_ssid)
      |> assign(wifi_ip: wifi_ip)
      |> assign(usb_ip: usb_ip)
      |> assign(battery_percentage: battery_percentage)
      |> assign(charging_status: charging_status)

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, screen) do
    # Button A = Next (rotates forward)
    num_sections = length(@sections)
    new_index = rem(screen.assigns.scroll_index + 1, num_sections)
    {:noreply, assign(screen, scroll_index: new_index)}
  end

  def handle_button(:button_2, :single_press, screen) do
    # Button B = Prev (rotates backward)
    num_sections = length(@sections)
    new_index = rem(screen.assigns.scroll_index - 1 + num_sections, num_sections)
    {:noreply, assign(screen, scroll_index: new_index)}
  end

  def handle_button(:button_2, :long_press, screen) do
    # Long B = Exit
    {:noreply, navigate(screen, :back)}
  end

  def handle_button(_button, _press_type, screen) do
    {:noreply, screen}
  end

  defp get_version do
    case Application.spec(:name_badge, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "Unknown"
    end
  end

  defp get_wifi_ssid do
    case NameBadge.Network.current_ap() do
      nil -> "Not connected"
      ssid -> ssid
    end
  end

  defp get_wifi_ip do
    NameBadge.Network.wlan_ip()
  end

  defp get_usb_ip do
    NameBadge.Network.usb_ip()
  end

  defp get_battery_info do
    percentage = NameBadge.Battery.percentage()
    charging = NameBadge.Battery.charging?()
    {percentage, format_charging_status(charging)}
  end

  defp format_charging_status(true), do: "Charging"
  defp format_charging_status(false), do: "On Battery"
end
