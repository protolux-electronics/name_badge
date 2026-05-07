defmodule NameBadge.Screen.ExRatatui do
  @moduledoc """
  `NameBadge.Screen` adapter that hosts an `ExRatatui.App`, ferries
  badge button events into it, and rasterises its rendered cell buffer
  through the existing `NameBadge.Display.render_png/2` pipeline.

  ## Wiring

      ExRatatui.App
            │
            ▼
      ExRatatui.Server (started in `mount/2`)
            │  cell_writer_fn
            ▼
      send(screen_pid, {:ex_ratatui_diff, %CellSession.Diff{}})
            │
            ▼
      handle_info/2 → Raster.apply_diff/2 → Raster.to_png/1
            │
            ▼
      assign(screen, :png, png)
            │
            ▼
      base NameBadge.Screen sees assigns changed → render/1 returns
      the PNG → Display.render_png(png, refresh_type: :partial)

  ## Mount args

      mount: [
        app: MyTui,                  # required, implements ExRatatui.App
        app_opts: [],                # optional, forwarded to the App's mount/1
        key_map: %{...}              # optional, overrides the button mapping below
      ]

  ## Default key map

  | Badge input             | ExRatatui.Event.Key |
  | ----------------------- | ------------------- |
  | A (single press)        | `code: "up"`        |
  | A (long press)          | `code: "home"`      |
  | B (single press)        | `code: "down"`      |
  | B (long press)          | (intercepted by `NameBadge.Screen` for navigate `:back`) |

  Apps that need a different mapping (e.g. Snake-as-TUI wanting
  left/right) pass a `:key_map` keyed by `{:button_1 | :button_2,
  :single_press | :long_press}` whose values are
  `t:ExRatatui.Event.Key.t/0`.
  """

  use NameBadge.Screen

  alias ExRatatui.CellSession
  alias ExRatatui.Event.Key
  alias NameBadge.ExRatatui.Raster

  @default_key_map %{
    {:button_1, :single_press} => %Key{code: "up", kind: "press", modifiers: []},
    {:button_1, :long_press} => %Key{code: "home", kind: "press", modifiers: []},
    {:button_2, :single_press} => %Key{code: "down", kind: "press", modifiers: []}
  }

  @impl NameBadge.Screen
  def mount(args, screen) do
    app_mod = Keyword.fetch!(args, :app)
    app_opts = Keyword.get(args, :app_opts, [])
    key_map = Keyword.get(args, :key_map, @default_key_map)

    {cols, rows} = Raster.grid_size()
    session = CellSession.new(cols, rows)

    screen_pid = self()
    cell_writer = fn diff -> send(screen_pid, {:ex_ratatui_diff, diff}) end

    server_opts =
      [
        mod: app_mod,
        name: nil,
        transport: {:cell_session, session, cell_writer}
      ] ++ app_opts

    {:ok, server} = ExRatatui.Transport.start_server(server_opts)

    {:ok,
     screen
     |> assign(:server, server)
     |> assign(:session, session)
     |> assign(:key_map, key_map)
     |> assign(:raster, Raster.new())
     |> assign(:png, blank_png())}
  end

  @impl NameBadge.Screen
  def render(assigns), do: assigns.png

  @impl NameBadge.Screen
  def handle_button(button, press_type, screen) do
    case Map.fetch(screen.assigns.key_map, {button, press_type}) do
      {:ok, %Key{} = event} ->
        send(screen.assigns.server, {:ex_ratatui_event, event})
        {:noreply, screen}

      :error ->
        {:noreply, screen}
    end
  end

  @impl NameBadge.Screen
  def handle_info({:ex_ratatui_diff, diff}, screen) do
    raster = Raster.apply_diff(screen.assigns.raster, diff)
    png = Raster.to_png(raster)

    {:noreply,
     screen
     |> assign(:raster, raster)
     |> assign(:png, png)}
  end

  def handle_info(_other, screen), do: {:noreply, screen}

  @impl NameBadge.Screen
  def terminate(_reason, screen) do
    if session = screen.assigns[:session], do: CellSession.close(session)
    :ok
  end

  defp blank_png(), do: Raster.new() |> Raster.to_png()
end
