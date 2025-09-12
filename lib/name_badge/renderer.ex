defmodule NameBadge.Renderer do
  @moduledoc """
  Renders a Screen to the Display.
  """

  require Logger

  alias NameBadge.Socket
  alias NameBadge.Wlan

  def render(render_type, screen) do
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

    connected? = Wlan.connected?()
    wifi_icon = if connected?, do: "wifi.png", else: "wifi-slash.png"
    link_icon = if Socket.connected?(), do: "link.png", else: "link-slash.png"

    markup =
      """
      #set page(width: 400pt, height: 300pt, margin: 32pt);

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

      <%= if @button_hints do %>
      #place(
        top + left,
        dx: -28pt,
        stack(dir: ttb, spacing: 16pt,
          circle(radius: 8pt, stroke: 1.25pt)[
            #set align(center + horizon)
            #text(size: 16pt, weight: "bold", font: "New Amsterdam", "A")
          ],
          circle(radius: 8pt, stroke: 1.25pt)[
            #set align(center + horizon)
            #text(size: 16pt, weight: "bold", font: "New Amsterdam", "B")
          ],
        )
      );

      #place(bottom + center, dy: 24pt,
        stack(dir: ltr, spacing: 20pt,
          <%= if @button_hints.a do %>
            stack(dir: ltr, spacing: 8pt,
              circle(radius: 8pt, stroke: 1.25pt)[
                #set align(center + horizon)
                #text(size: 16pt, weight: "bold", font: "New Amsterdam", "A")
              ],
              align(horizon, text(size: 20pt, font: "New Amsterdam", "<%= @button_hints.a %>"))
            ),
          <% end %>

          <%= if @button_hints.b  do %>
            stack(dir: ltr, spacing: 8pt,
              circle(radius: 8pt, stroke: 1.25pt)[
                #set align(center + horizon)
                #text(size: 16pt, weight: "bold", font: "New Amsterdam", "B")
              ],
              align(horizon, text(size: 20pt, font: "New Amsterdam", "<%= @button_hints.b %>"))
            )
          <% end %>
        )
      );

      <% end %>

      #{screen.module.render(screen.assigns)}
      """

    button_hints = Map.get(screen.assigns, :button_hints)

    with {:ok, [png | _rest]} <-
           Typst.render_to_png(markup, [assigns: [button_hints: button_hints]],
             root_dir: Application.app_dir(:name_badge, "priv/typst"),
             extra_fonts: [Application.app_dir(:name_badge, "priv/typst/fonts")]
           ),
         {:ok, img} = Dither.decode(png),
         {:ok, gray} = Dither.grayscale(img),
         {:ok, raw} = Dither.to_raw(gray) do
      NameBadge.Display.draw(raw, render_type: render_type)
    else
      error -> Logger.error("rendering error: #{inspect(error)}")
    end
  end
end
