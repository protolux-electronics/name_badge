defmodule NameBadge.Renderer do
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

    screen = %Screen{module: Screen.TopLevel}
    {:ok, screen} = Screen.TopLevel.init([], screen)

    {:ok, %{btn_1: btn_1, btn_2: btn_2, stack: [], current_screen: screen}, {:continue, :render}}
  end

  @impl true
  def handle_continue(:render, state) do
    state =
      case state.current_screen do
        %Screen{action: :back} ->
          [prev_screen | rest] = state.stack
          Map.merge(state, %{stack: rest, current_screen: prev_screen})

        %Screen{action: {:navigate, module, params}} = screen ->
          new_stack = [Map.put(screen, :action, nil) | state.stack]

          new_screen = %Screen{module: module}
          {:ok, new_screen} = module.init(params, new_screen)

          Map.merge(state, %{stack: new_stack, current_screen: new_screen})

        _screen ->
          state
      end

    render_screen(state.current_screen)

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

  def handle_info({:assign, key, value}, state) do
    state = %{state | current_screen: Screen.assign(state.current_screen, key, value)}
    {:noreply, state, {:continue, :render}}
  end

  def handle_info({:survey_question, question}, state) do
    screen = Screen.navigate(state.current_screen, NameBadge.Screen.Survey, question)
    state = %{state | current_screen: screen}

    {:noreply, state, {:continue, :render}}
  end

  defp render_screen(screen) do
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

    connected? = VintageNet.get(["interface", "wlan0", "connection"]) == :internet
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
          image("images/icons/#{wifi_icon}"), image("images/icons/#{link_icon}"), 
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
      NameBadge.Display.draw(raw)
    else
      error -> Logger.error("rendering error: #{inspect(error)}")
    end
  end
end
