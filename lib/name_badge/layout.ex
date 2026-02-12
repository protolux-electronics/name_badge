defmodule NameBadge.Layout do
  @wlan0_property ["interface", "wlan0", "connection"]

  def root_layout(content, opts \\ []) do
    width = Keyword.get(opts, :width, 648)
    height = Keyword.get(opts, :height, 480)
    margin = Keyword.get(opts, :margin, 32)

    """
    #set page(width: #{width}pt, height: #{height}pt, margin: #{margin}pt);
    #set text(font: "Poppins", size: 20pt, weight: 500)

    #{content}
    """
  end

  def app_layout(content, opts \\ []) do
    buttons = Keyword.get(opts, :button_hints, %{})

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

    wifi_icon =
      if NameBadge.Network.connected?(@wlan0_property), do: "wifi.png", else: "wifi-slash.png"

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

  defp buttons_markup(button_hints) do
    hint_text = [a: "A", b: "B", ab: "AB"]

    hints =
      Enum.map(hint_text, fn {key, hint_letter} ->
        button_hint(hint_letter, Map.get(button_hints, key))
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    """
    #place(
      top + left,
      dx: -28pt,
      dy: 4pt,
      stack(dir: ttb, spacing: 8pt,
      #{button_circle("A")},
      #{button_circle("B")},
      )
    );

    #place(bottom + center, dy: 24pt,
      stack(dir: ltr, spacing: 20pt, #{hints})
    ); 
    """
  end

  defp button_hint(_button, nil), do: nil

  defp button_hint(letter, hint_text) do
    """
    stack(dir: ltr, spacing: 8pt,
      #{button_circle(letter)},
      align(horizon, text[#{hint_text}])
    )
    """
  end

  defp button_circle(letter) do
    """
    circle(radius: 9pt, stroke: 1.25pt)[
      #set align(center + horizon)
      #text(size: 16pt, font: "New Amsterdam", "#{letter}")
    ]
    """
  end
end
