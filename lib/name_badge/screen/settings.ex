defmodule NameBadge.Screen.Settings do
  use NameBadge.Screen

  alias NameBadge.Battery
  alias NameBadge.Socket

  require Logger

  def render(%{connected: false}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 16pt,
        text(size: 48pt, font: "New Amsterdam", "Not connected :(")
      )
    );
    """
  end

  def render(%{show_stats: true}) do
    current_ap =
      case VintageNet.get(["interface", "wlan0", "wifi", "current_ap"]) do
        %{ssid: ssid} -> ssid
        _ -> nil
      end

    wlan_ip =
      case VintageNet.get(["interface", "wlan0", "addresses"])
           |> Enum.find(&(&1.family == :inet)) do
        %{address: {a1, a2, a3, a4}} -> "#{a1}.#{a2}.#{a3}.#{a4}"
        _ -> nil
      end

    usb_ip =
      case VintageNet.get(["interface", "wlan0", "addresses"])
           |> Enum.find(&(&1.family == :inet)) do
        %{address: {a1, a2, a3, a4}} -> "#{a1}.#{a2}.#{a3}.#{a4}"
        _ -> nil
      end

    """
    #grid(
      columns: (1fr, 1fr),
      gutter: 16pt,
      [
        #set align(top + center);
        #text(size: 18pt, font: "New Amsterdam")[
          #heading()[Partition A]
          Active?: #{Nerves.Runtime.KV.get("nerves_fw_active") == "a"} \\
          Version: #{Nerves.Runtime.KV.get("a.nerves_fw_version")} \\
          UUID: #{Nerves.Runtime.KV.get("a.nerves_fw_uuid") |> String.split_at(16) |> elem(0)}

          #heading()[Battery]
          Voltage: #{Float.round(Battery.voltage(), 3)}V \\
        ]
      ],
      [
        #set align(top + center);
        #text(size: 18pt, font: "New Amsterdam")[
          #heading()[Partition B]
          Active?: #{Nerves.Runtime.KV.get("nerves_fw_active") == "b"} \\
          Version: #{Nerves.Runtime.KV.get("b.nerves_fw_version")} \\
          UUID: #{Nerves.Runtime.KV.get("b.nerves_fw_uuid") |> String.split_at(16) |> elem(0)}

          #heading()[Networking]
          wlan0: #{wlan_ip} \\
          #{if current_ap, do: "SSID: " <> current_ap}

          usb0: #{usb_ip} \\
        ]
      ],
    )
    """
  end

  def render(assigns) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 12pt,
        image(height: 80%, format: "svg", bytes("#{assigns.qr_code}")),
        v(8pt),
        text(size: 24pt, font: "New Amsterdam", "Scan to modify settings"),
      )
    );
    """
  end

  def init(_args) do
    cond do
      Socket.connected?() ->
        token =
          :crypto.strong_rand_bytes(16)
          |> Base.encode16()

        Socket.join_config(token, %{})

        url = "https://#{base_url()}/device/#{token}/config"

        Logger.info("Generated QR code for: #{url}")

        {:ok, qr_code_svg} =
          url
          |> QRCode.create()
          |> QRCode.render()

        {:ok,
         %{
           qr_code: encode(qr_code_svg),
           token: token,
           show_stats: false,
           button_hints: %{a: "Stats for nerds", b: "Back"}
         }}

      true ->
        {:ok, %{connected: false}}
    end
  end

  def handle_button("BTN_1", 0, screen) do
    button_a_label = if screen.assigns.show_stats, do: "Stats for nerds", else: "Scan QR code"

    screen =
      screen
      |> assign(:show_stats, not screen.assigns.show_stats)
      |> assign(:button_hints, %{a: button_a_label, b: "Back"})

    {:render, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    if screen.assigns[:token], do: Socket.leave_config(screen.assigns.token)

    {:render, navigate(screen, :back)}
  end

  def handle_button(_, _, screen) do
    {:norender, screen}
  end

  defp base_url(), do: Application.get_env(:name_badge, :base_url)

  defp encode(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
