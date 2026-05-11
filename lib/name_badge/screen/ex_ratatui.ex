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
        app: MyTui,                  # required; the module MUST `use ExRatatui.App`
        app_opts: [],                # optional, forwarded to the App's mount/1
        key_map: %{...}              # optional, overrides the button mapping below
      ]

  > **Why `use ExRatatui.App` and not just `@behaviour`?** The runtime
  > calls `mod.__runtime__/0` to dispatch between the callback and
  > reducer styles. That function is injected by `use ExRatatui.App`
  > and does not exist on a module that only declares
  > `@behaviour ExRatatui.App`. The adapter raises an `ArgumentError`
  > at `mount/2` if the App module is missing it.

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

  require Logger

  alias ExRatatui.CellSession
  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph
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

    ensure_ex_ratatui_app!(app_mod)

    # Trap exits so we can catch a crashed Server, render a fallback
    # frame, and stay on screen until the user long-presses B to go
    # back — instead of dying via the link and leaving the badge stuck
    # on the last good frame.
    Process.flag(:trap_exit, true)

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

    # The Server's first render fires the cell_writer synchronously
    # during init, so by the time start_server returns, the initial
    # diff is already in our mailbox. Drain it now and seed assigns
    # with real content — otherwise the base Screen's first render
    # paints a blank PNG before our handle_info catches up, causing a
    # one-frame flicker on every screen switch.
    {raster, png} = drain_initial_frame(Raster.new())

    {:ok,
     screen
     |> assign(:server, server)
     |> assign(:session, session)
     |> assign(:key_map, key_map)
     |> assign(:raster, raster)
     |> assign(:png, png)}
  end

  @impl NameBadge.Screen
  def render(assigns), do: assigns.png

  @impl NameBadge.Screen
  def handle_button(_button, _press_type, %{assigns: %{server: nil}} = screen) do
    # Server crashed earlier; the user is looking at a "TUI CRASHED"
    # frame. Forwarding events would crash us too. Long-press B is
    # intercepted by the base Screen for navigate :back, so the user
    # can still get out.
    {:noreply, screen}
  end

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

  def handle_info(
        {:EXIT, pid, reason},
        %{assigns: %{server: server}} = screen
      )
      when pid == server do
    Logger.error("ExRatatui.Server crashed: #{inspect(reason)}")

    {:noreply,
     screen
     |> assign(:server, nil)
     |> assign(:png, crashed_png())}
  end

  def handle_info(_other, screen), do: {:noreply, screen}

  @impl NameBadge.Screen
  def terminate(_reason, screen) do
    if session = screen.assigns[:session], do: CellSession.close(session)
    :ok
  end

  defp blank_png(), do: Raster.new() |> Raster.to_png()

  # Awaits the first cell_writer message and folds it into the
  # provided raster. Falls back to a blank PNG if no diff is
  # delivered within @initial_frame_timeout — better to start with
  # blank and update on the next handle_info than to deadlock the
  # screen.
  #
  # 100ms is comfortably above the observed first-render time
  # (synchronous in the Server's init/1 plus a single send) on the
  # badge — even under cold load the first diff has always landed
  # well under that. Bump if a future app does heavy work in its
  # mount/1.
  @initial_frame_timeout 100
  defp drain_initial_frame(raster) do
    receive do
      {:ex_ratatui_diff, diff} ->
        raster = Raster.apply_diff(raster, diff)
        {raster, Raster.to_png(raster)}
    after
      @initial_frame_timeout -> {raster, blank_png()}
    end
  end

  defp crashed_png() do
    {cols, rows} = Raster.grid_size()
    session = CellSession.new(cols, rows)

    mid = div(rows, 2)

    widgets = [
      {%Paragraph{text: "TUI CRASHED", alignment: :center},
       %Rect{x: 0, y: mid - 1, width: cols, height: 1}},
      {%Paragraph{text: "LONG-PRESS B FOR MENU", alignment: :center},
       %Rect{x: 0, y: mid + 1, width: cols, height: 1}}
    ]

    :ok = CellSession.draw(session, widgets)
    snapshot = CellSession.take_cells(session)
    :ok = CellSession.close(session)

    Raster.new()
    |> Raster.put_snapshot(snapshot)
    |> Raster.to_png()
  end

  defp ensure_ex_ratatui_app!(app_mod) do
    case Code.ensure_loaded(app_mod) do
      {:module, ^app_mod} ->
        if function_exported?(app_mod, :__runtime__, 0) do
          :ok
        else
          raise ArgumentError, """
          #{inspect(app_mod)} does not export __runtime__/0 — did you
          forget `use ExRatatui.App`?

          Declaring `@behaviour ExRatatui.App` alone is not enough; the
          runtime relies on __runtime__/0 to choose between the callback
          and reducer styles. Switch to `use ExRatatui.App` and the
          function will be injected for you.
          """
        end

      {:error, _reason} ->
        raise ArgumentError,
              "App module #{inspect(app_mod)} could not be loaded. " <>
                "Check the spelling and make sure it compiles."
    end
  end

  @doc """
  Generates a `NameBadge.Screen` module that hosts a fixed
  `ExRatatui.App`. Use this from per-demo menu-facing screens that the
  top-level menu can navigate to without passing mount args (which
  `NameBadge.ScreenManager.navigate/1` does not carry).

      defmodule NameBadge.Screen.Counter do
        use NameBadge.Screen.ExRatatui, app: NameBadge.Screen.ExRatatui.Counter
      end

  Accepts the same options as `mount/2`:

    * `:app` (required) — module implementing `ExRatatui.App`.
    * `:app_opts` (optional) — keyword list forwarded to
      `ExRatatui.Server` and the App's `mount/1`.
    * `:key_map` (optional) — overrides the default badge-button to
      `t:ExRatatui.Event.Key.t/0` mapping.
  """
  defmacro __using__(opts) do
    app = Keyword.fetch!(opts, :app)
    app_opts = Keyword.get(opts, :app_opts, [])
    key_map = Keyword.get(opts, :key_map, nil)

    quote do
      use NameBadge.Screen

      @adapter NameBadge.Screen.ExRatatui
      @adapter_args [
        app: unquote(app),
        app_opts: unquote(app_opts)
      ]
      @adapter_key_map unquote(key_map)

      @impl NameBadge.Screen
      def mount(_args, screen) do
        adapter_args =
          if @adapter_key_map,
            do: [{:key_map, @adapter_key_map} | @adapter_args],
            else: @adapter_args

        @adapter.mount(adapter_args, screen)
      end

      @impl NameBadge.Screen
      def render(assigns), do: @adapter.render(assigns)

      @impl NameBadge.Screen
      def handle_button(button, press_type, screen),
        do: @adapter.handle_button(button, press_type, screen)

      @impl NameBadge.Screen
      def handle_info(message, screen), do: @adapter.handle_info(message, screen)

      @impl NameBadge.Screen
      def terminate(reason, screen), do: @adapter.terminate(reason, screen)
    end
  end
end
