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
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Firmware Info

    Active Partition: #{assigns.version.active}

    Partition A:
    - Version: #{assigns.version.a}
    - UUID: #{if assigns.version.a_uuid, do: String.slice(assigns.version.a_uuid, 0..18) <> "...", else: "N/A"}

    Partition B:
    - Version: #{assigns.version.b || "N/A"} 
    - UUID: #{if assigns.version.b_uuid, do: String.slice(assigns.version.b_uuid, 0..18) <> "...", else: "N/A"}
    """
  end

  defp render_network(assigns) do
    """
    #set text(size: 18pt)
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Network Info

    - WiFi SSID: #{assigns.wifi_ssid}
    - WiFi IP: #{assigns.wifi_ip}
    - USB IP: #{assigns.usb_ip}
    """
  end

  defp render_battery(assigns) do
    """
    #set text(size: 18pt)
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Power Info

    - Battery: #{assigns.battery.percentage}%
    - Voltage: #{assigns.battery.voltage}V
    - Status: #{assigns.battery.charging_status}
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

    battery_info = get_battery_info()

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
      |> assign(battery: battery_info)

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

  if Mix.target() == :host do
    defp get_version do
      %{
        active: "A",
        a: "1.2.3",
        a_uuid: "MOCKED-e29b-41d4-a716-446655440000",
        b: "1.2.4",
        b_uuid: "MOCKED-e29b-41d4-a716-446655440000"
      }
    end
  else
    def get_version do
      %{
        active: Nerves.Runtime.KV.get("nerves_fw_active") |> String.upcase(),
        a: Nerves.Runtime.KV.get("a.nerves_fw_version"),
        a_uuid: Nerves.Runtime.KV.get("a.nerves_fw_uuid"),
        b: Nerves.Runtime.KV.get("b.nerves_fw_version"),
        b_uuid: Nerves.Runtime.KV.get("b.nerves_fw_uuid")
      }
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

    voltage =
      NameBadge.Battery.voltage()
      |> Float.round(2)

    %{percentage: percentage, charging_status: format_charging_status(charging), voltage: voltage}
  end

  defp format_charging_status(true), do: "Charging"
  defp format_charging_status(false), do: "On Battery"
end
