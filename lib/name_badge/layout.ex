defmodule NameBadge.Layout do
  @wlan0_property ["interface", "wlan0", "connection"]

  def root_layout(content, opts \\ []) do
    width = Keyword.get(opts, :width, 400)
    height = Keyword.get(opts, :height, 300)
    margin = Keyword.get(opts, :margin, 32)

    """
    #set page(width: #{width}pt, height: #{height}pt, margin: #{margin}pt);

    #{content}
    """
  end

  def app_layout(content, opts \\ []) do
    buttons = Keyword.get(opts, :buttons, [])

    app_layout =
      """
      #{icons_markup()}
      #{buttons_markup(buttons)}

      #{content}
      """

    root_layout(app_layout, opts)
  end

  defp icons_markup() do
    voltage = NameBadge.Battery.voltage()

    battery_icon =
      cond do
        NameBadge.Battery.charging?() -> "battery-charging.png"
        voltage > 4.0 -> "battery-100.png"
        voltage > 3.8 -> "battery-75.png"
        voltage > 3.6 -> "battery-50.png"
        voltage > 3.4 -> "battery-25.png"
        true -> "battery-0.png"
      end

    wlan_connected? = VintageNet.get(@wlan0_property) == :internet
    wifi_icon = if wlan_connected?, do: "wifi.png", else: "wifi-slash.png"
    link_icon = if NameBadge.Socket.connected?(), do: "link.png", else: "link-slash.png"

    """
    #place(
      top + right,
      dy: -24pt,
      dx: 24pt,
      box(height: 16pt, stack(dir: ltr, spacing: 8pt,
        image("images/icons/#{battery_icon}"),
        image("images/icons/#{wifi_icon}"),
        image("images/icons/#{link_icon}"),
      ))
    )
    """
  end

  # TODO: implement button icons and help text
  defp buttons_markup(_button_hints), do: ""
end
