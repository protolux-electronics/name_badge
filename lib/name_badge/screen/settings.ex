defmodule NameBadge.Screen.Settings do
  use NameBadge.Screen

  alias NameBadge.Display
  alias NameBadge.Battery
  alias NameBadge.Socket

  require Logger

  def render(%{show_stats: true}) do
    current_ap =
      case VintageNet.get(["interface", "wlan0", "wifi", "current_ap"]) do
        %{ssid: ssid} -> ssid
        _ -> nil
      end

    wlan_ip =
      case VintageNet.get(["interface", "wlan0", "addresses"]) do
        addrs when is_list(addrs) ->
          case Enum.find(addrs, &(&1.family == :inet)) do
            %{address: {a1, a2, a3, a4}} ->
              "#{a1}.#{a2}.#{a3}.#{a4}"

            _other ->
              "Not connected"
          end

        _ ->
          "Not connected"
      end

    usb_ip =
      case VintageNet.get(["interface", "usb0", "addresses"]) do
        addrs when is_list(addrs) ->
          case Enum.find(addrs, &(&1.family == :inet)) do
            %{address: {a1, a2, a3, a4}} ->
              "#{a1}.#{a2}.#{a3}.#{a4}"

            _other ->
              "Not connected"
          end

        _ ->
          "Not connected"
      end

    firmware = fn
      nil ->
        "null"

      fw ->
        {first, rest} = String.split_at(fw, 8)
        {_junk, last} = String.split_at(rest, -4)

        "#{first}...#{last}"
    end

    battery = Float.round(Battery.voltage(), 3)

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
          UUID: #{Nerves.Runtime.KV.get("a.nerves_fw_uuid") |> firmware.()}

          #heading()[Battery]
          #{if Battery.charging?(), do: "Status: Charging", else: "Voltage: " <> to_string(battery) <> "V"} \\
        ]
      ],
      [
        #set align(top + center);
        #text(size: 18pt, font: "New Amsterdam")[
          #heading()[Partition B]
          Active?: #{Nerves.Runtime.KV.get("nerves_fw_active") == "b"} \\
          Version: #{Nerves.Runtime.KV.get("b.nerves_fw_version")} \\
          UUID: #{Nerves.Runtime.KV.get("b.nerves_fw_uuid") |> firmware.()}

          #heading()[Networking]
          wlan0: #{wlan_ip} \\
          #{if current_ap, do: "SSID: " <> current_ap}

          usb0: #{usb_ip} \\
        ]
      ],
    )
    """
  end

  def render(%{connected: false}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 16pt,
        text(size: 48pt, font: "New Amsterdam", "Not connected :(")
      )
    );
    """
  end

  def render(%{qr_code: qr_code}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 12pt,
        image(height: 80%, format: "svg", bytes("#{qr_code}")),
        v(8pt),
        text(size: 24pt, font: "New Amsterdam", "Scan to modify settings"),
      )
    );
    """
  end

  def init(_args, screen) do
    screen =
      cond do
        Socket.connected?() ->
          token =
            :crypto.strong_rand_bytes(16)
            |> Base.encode16()

          config = NameBadge.Config.load_config() || %{}
          Socket.join_config(token, config)

          url = "https://#{base_url()}/device/#{token}/config"

          Logger.info("Generated QR code for: #{url}")

          {:ok, qr_code_svg} =
            url
            |> QRCode.create()
            |> QRCode.render()

          screen
          |> assign(:connected, true)
          |> assign(:qr_code, encode(qr_code_svg))
          |> assign(:token, token)
          |> assign(:show_stats, false)
          |> assign(:sudo_mode, false)

        true ->
          screen
          |> assign(:connected, false)
          |> assign(:show_stats, false)
          |> assign(:sudo_mode, false)
      end

    {:ok, assign(screen, :button_hints, %{a: "Stats for nerds", b: "Back"})}
  end

  def handle_button(_which, 0, %{assigns: %{sudo_mode: true}} = screen), do: {:norender, screen}

  def handle_button("BTN_1", 0, screen) do
    button_a_label = if screen.assigns.show_stats, do: "Stats for nerds", else: "Enter Sudo Mode"

    cond do
      screen.assigns.show_stats ->
        Task.start_link(fn ->
          frames =
            Application.app_dir(:name_badge, "priv/sudo_mode.bin")
            |> File.read!()
            |> :erlang.binary_to_term()

          for frame <- frames, do: Display.draw(frame, refresh_type: :partial)

          send(NameBadge.Renderer, {:assign, :sudo_mode, false})
        end)

        {:norender, assign(screen, :sudo_mode, true)}

      true ->
        screen =
          screen
          |> assign(:show_stats, not screen.assigns.show_stats)
          |> assign(:button_hints, %{a: button_a_label, b: "Back"})

        {:render, screen}
    end
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
