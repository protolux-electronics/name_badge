defmodule NameBadge.ScreenManager do
  use GenServer

  require Logger

  alias NameBadge.ButtonMonitor
  alias NameBadge.Screen

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    ButtonMonitor.subscribe_to_button(:button_1)
    ButtonMonitor.subscribe_to_button(:button_2)

    {:ok, pid} = Screen.start_link(module: Screen.TopLevel)
    send(self(), :render)

    {:ok, %{stack: [], current_screen: pid, last_render_hash: nil}}
  end

  @impl GenServer
  def handle_info(:render, state) do
    markup =
      state.current_screen
      |> Screen.render()
      |> wrap_template()

    hash = :erlang.phash2(markup)

    if state.last_render_hash != hash do
      typst_opts = [root_dir: typst_dir(), extra_fonts: [fonts_dir()]]

      with {:ok, [png | _rest]} <- Typst.render_to_png(markup, [], typst_opts),
           {:ok, img} = Dither.decode(png),
           {:ok, gray} = Dither.grayscale(img),
           {:ok, raw} = Dither.to_raw(gray) do
        NameBadge.Display.draw(raw)
      else
        error -> Logger.error("rendering error: #{inspect(error)}")
      end
    end

    {:noreply, %{state | last_render_hash: hash}}
  end

  def handle_info({:button_event, which_button, press_type}, state) do
    Screen.handle_button(state.current_screen, which_button, press_type)
    send(self(), :render)

    {:noreply, state}
  end

  defp wrap_template(content, button_hints \\ []) do
    """
    #set page(width: 400pt, height: 300pt, margin: 32pt);

    #{render_icons()}

    #{render_button_hints(button_hints)}

    #{content}
    """
  end

  defp render_icons() do
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

  # TODO: implement button hints
  defp render_button_hints(_button_hints), do: ""

  defp typst_dir, do: Application.app_dir(:name_badge, "priv/typst")
  defp fonts_dir, do: Path.join(typst_dir(), "fonts")

  defp hash_render(markup), do: :erlang.phash2(markup)
end
