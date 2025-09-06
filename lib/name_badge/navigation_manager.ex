defmodule NameBadge.NavigationManager do
  use GenServer

  require Logger

  alias NameBadge.Screen
  alias NameBadge.Socket
  alias Circuits.GPIO

  @btn_1 "BTN_1"
  @btn_2 "BTN_2"

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, btn_1} = GPIO.open(@btn_1, :input)
    {:ok, btn_2} = GPIO.open(@btn_2, :input)

    GPIO.set_interrupts(btn_1, :both)
    GPIO.set_interrupts(btn_2, :both)

    {:ok, top_level_assigns} = Screen.TopLevel.init([])
    top_level = %Screen{assigns: top_level_assigns, module: Screen.TopLevel}

    {:ok, %{btn_1: btn_1, btn_2: btn_2, stack: [], current_screen: top_level},
     {:continue, :render}}
  end

  @impl true
  def handle_continue(:render, state) do
    battery_level =
      case NameBadge.Battery.voltage() do
        val when val > 4.0 -> 100
        val when val > 3.8 -> 75
        val when val > 3.6 -> 50
        val when val > 3.4 -> 25
        val when val > 3.2 -> 0
        _true -> 0
      end

    connected? = VintageNet.get(["interface", "wlan0", "connection"]) == :internet
    wifi_icon = if connected?, do: "wifi.svg", else: "wifi-slash.svg"
    link_icon = if Socket.connected?(), do: "link.svg", else: "link-slash.svg"

    markup =
      """
      #set page(width: 400pt, height: 300pt, margin: 32pt);

      #place(
        top + right,
        dy: -24pt,
        dx: 24pt,
        box(height: 16pt, stack(dir: ltr, spacing: 8pt,
          image("images/icons/battery-#{battery_level}.svg"), 
          image("images/icons/#{wifi_icon}"), image("images/icons/#{link_icon}"), 
        ))
      )

      #{state.current_screen.module.render(state.current_screen.assigns)}
      """

    with {:ok, [png]} <-
           Typst.render_to_png(markup, [],
             root_dir: Application.app_dir(:name_badge, "priv/typst"),
             extra_fonts: [Application.app_dir(:name_badge, "priv/typst/fonts")]
           ),
         {:ok, img} = Dither.decode(png),
         {:ok, gray} = Dither.grayscale(img),
         {:ok, raw} = Dither.to_raw(gray) do
      NameBadge.Display.draw(raw)
    else
      error -> Logger.error("rendering error: #{inspect(error)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_gpio, which_button, _ts, value}, state) do
    Logger.info("button pressed: #{which_button} - #{value}")

    case state.current_screen.module.handle_button(which_button, value, state.current_screen) do
      {:render, screen} ->
        {:noreply, put_in(state.current_screen, screen), {:continue, :render}}

      {:norender, screen} ->
        {:noreply, put_in(state.current_screen, screen)}
    end
  end
end
