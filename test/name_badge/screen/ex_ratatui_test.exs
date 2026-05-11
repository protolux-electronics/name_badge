defmodule NameBadge.Screen.ExRatatuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.CellSession.{Cell, Diff}
  alias ExRatatui.Event.Key
  alias NameBadge.ExRatatui.Raster
  alias NameBadge.Screen
  alias NameBadge.Screen.ExRatatui, as: Adapter

  defmodule MerelyBehaviourApp do
    @moduledoc false
    # Intentionally declares the behaviour but does NOT `use
    # ExRatatui.App`, so __runtime__/0 is never injected. This is the
    # exact mistake that crashed Counter at runtime — the adapter must
    # detect it at mount time and raise a clear error.
    @behaviour ExRatatui.App

    @impl true
    def mount(_), do: {:ok, %{}}

    @impl true
    def render(_, _), do: []

    @impl true
    def handle_event(_, state), do: {:noreply, state}
  end

  defmodule HelloApp do
    @moduledoc false
    # A minimal correctly-defined ExRatatui.App used to smoke-test the
    # full adapter → Server → CellSession → cell_writer path.
    use ExRatatui.App

    alias ExRatatui.Layout.Rect
    alias ExRatatui.Widgets.Paragraph

    @impl true
    def mount(_opts), do: {:ok, %{}}

    @impl true
    def render(_state, frame) do
      [
        {%Paragraph{text: "HI"}, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  describe "mount/2 against a real Server" do
    setup do
      # ExRatatui.Server emits :telemetry events on init; without the
      # app running, they log "Failed to lookup telemetry handlers"
      # warnings that drown legitimate test output. Starting :telemetry
      # is enough to keep them quiet — we don't actually attach any
      # handlers.
      {:ok, _} = Application.ensure_all_started(:telemetry)
      :ok
    end

    test "starts the Server and seeds non-blank initial content into assigns" do
      {:ok, screen} = Adapter.mount([app: HelloApp], %Screen{module: Adapter})

      on_exit(fn -> stop_server(screen) end)

      assert is_pid(screen.assigns.server)
      assert Process.alive?(screen.assigns.server)
      assert %ExRatatui.CellSession{} = screen.assigns.session

      # mount/2 drains the Server's first cell_writer message and
      # folds it into the raster before returning, so :png is real
      # content — not the blank fallback. This is what kills the
      # one-frame blank flicker on every screen switch.
      blank = NameBadge.ExRatatui.Raster.new() |> NameBadge.ExRatatui.Raster.to_png()
      assert <<137, 80, 78, 71, _::binary>> = screen.assigns.png
      assert screen.assigns.png != blank
      assert screen.assigns.raster.cells != %{}
    end
  end

  describe "mount/2 guard" do
    test "raises a helpful error when the app module isn't `use ExRatatui.App`" do
      msg =
        try do
          Adapter.mount([app: MerelyBehaviourApp], %Screen{module: Adapter})
        rescue
          e in ArgumentError -> Exception.message(e)
        end

      assert msg =~ "does not export __runtime__/0"
      assert msg =~ "use ExRatatui.App"
    end

    test "raises a clear error when the app module can't be loaded at all" do
      msg =
        try do
          Adapter.mount([app: NotAModule.At.All], %Screen{module: Adapter})
        rescue
          e in ArgumentError -> Exception.message(e)
        end

      assert msg =~ "could not be loaded"
    end
  end

  describe "handle_button/3" do
    test "forwards single A as Key{code: \"up\"} to the server" do
      screen = screen_with_server()

      assert {:noreply, _} = Adapter.handle_button(:button_1, :single_press, screen)

      assert_receive {:ex_ratatui_event, %Key{code: "up", kind: "press", modifiers: []}}
    end

    test "forwards long A as Key{code: \"home\"}" do
      screen = screen_with_server()

      assert {:noreply, _} = Adapter.handle_button(:button_1, :long_press, screen)

      assert_receive {:ex_ratatui_event, %Key{code: "home"}}
    end

    test "forwards single B as Key{code: \"down\"}" do
      screen = screen_with_server()

      assert {:noreply, _} = Adapter.handle_button(:button_2, :single_press, screen)

      assert_receive {:ex_ratatui_event, %Key{code: "down"}}
    end

    test "ignores button combinations that aren't in the key map" do
      # Long-press B is reserved by NameBadge.Screen for navigate :back —
      # the adapter never sees it. But guard against any future button
      # the framework forwards through that we haven't mapped yet.
      screen = screen_with_server()

      assert {:noreply, ^screen} = Adapter.handle_button(:button_2, :long_press, screen)
      refute_received {:ex_ratatui_event, _}
    end

    test "honours a custom key map passed via mount args" do
      screen =
        screen_with_server(%{
          {:button_1, :single_press} => %Key{code: "left", kind: "press", modifiers: []},
          {:button_2, :single_press} => %Key{code: "right", kind: "press", modifiers: []}
        })

      Adapter.handle_button(:button_1, :single_press, screen)
      Adapter.handle_button(:button_2, :single_press, screen)

      assert_receive {:ex_ratatui_event, %Key{code: "left"}}
      assert_receive {:ex_ratatui_event, %Key{code: "right"}}
    end
  end

  describe "server crash handling" do
    test "an EXIT from the hosted server replaces the PNG with a crash frame and clears :server" do
      png_before = <<137, 80, 78, 71, 13, 10, 26, 10, "before">>

      fake_server = spawn(fn -> :ok end)

      screen = %Screen{
        module: Adapter,
        assigns: %{server: fake_server, png: png_before}
      }

      exit_msg = {:EXIT, fake_server, :killed}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:noreply, updated} = Adapter.handle_info(exit_msg, screen)

          assert updated.assigns.server == nil
          assert <<137, 80, 78, 71, _::binary>> = updated.assigns.png
          assert updated.assigns.png != png_before

          send(self(), {:result, updated})
        end)

      assert log =~ "ExRatatui.Server crashed"
      assert log =~ ":killed"
    end

    test "EXIT from an unrelated pid is ignored (treated as a stray message)" do
      stranger = spawn(fn -> :ok end)
      our_server = spawn(fn -> Process.sleep(:infinity) end)

      screen = %Screen{
        module: Adapter,
        assigns: %{server: our_server, png: <<>>}
      }

      assert {:noreply, ^screen} = Adapter.handle_info({:EXIT, stranger, :normal}, screen)
    end

    test "handle_button is a no-op once the server has been cleared" do
      screen = %Screen{
        module: Adapter,
        assigns: %{server: nil, key_map: default_key_map()}
      }

      assert {:noreply, ^screen} = Adapter.handle_button(:button_1, :single_press, screen)
      refute_received {:ex_ratatui_event, _}
    end
  end

  describe "handle_info/2 on cell diffs" do
    test "merges the diff into the raster and re-encodes the PNG" do
      screen = %Screen{
        module: Adapter,
        assigns: %{raster: Raster.new(), png: <<>>}
      }

      diff = %Diff{
        width: 66,
        height: 37,
        ops: [
          %Cell{
            col: 0,
            row: 0,
            symbol: "A",
            fg: :reset,
            bg: :reset,
            modifiers: [],
            skip: false
          }
        ]
      }

      assert {:noreply, updated} = Adapter.handle_info({:ex_ratatui_diff, diff}, screen)

      # PNG header.
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = updated.assigns.png

      # The raster carries one cell now.
      assert map_size(updated.assigns.raster.cells) == 1
      assert {%Cell{symbol: "A"}, _} = Map.pop!(updated.assigns.raster.cells, {0, 0})
    end

    test "ignores unrelated info messages" do
      screen = %Screen{module: Adapter, assigns: %{}}

      assert {:noreply, ^screen} = Adapter.handle_info(:something_else, screen)
      assert {:noreply, ^screen} = Adapter.handle_info({:unrelated, 1, 2}, screen)
    end
  end

  describe "terminate/2" do
    test "is safe to call without a session in assigns" do
      screen = %Screen{module: Adapter, assigns: %{}}

      assert :ok = Adapter.terminate(:normal, screen)
    end

    test "closes a CellSession in assigns" do
      session = ExRatatui.CellSession.new(10, 5)
      screen = %Screen{module: Adapter, assigns: %{session: session}}

      assert :ok = Adapter.terminate(:normal, screen)

      # Closed sessions return {:error, _} on draw — proves close took.
      assert {:error, _} = ExRatatui.CellSession.draw(session, [])
    end
  end

  # Builds a Screen struct whose `:server` assign is the test process
  # itself, so the adapter's `send(server, ...)` lands in this test's
  # mailbox where `assert_receive` can pick it up.
  defp screen_with_server(key_map \\ default_key_map()) do
    %Screen{
      module: Adapter,
      assigns: %{server: self(), key_map: key_map}
    }
  end

  defp default_key_map() do
    %{
      {:button_1, :single_press} => %Key{code: "up", kind: "press", modifiers: []},
      {:button_1, :long_press} => %Key{code: "home", kind: "press", modifiers: []},
      {:button_2, :single_press} => %Key{code: "down", kind: "press", modifiers: []}
    }
  end

  defp stop_server(screen) do
    if pid = screen.assigns[:server], do: GenServer.stop(pid, :normal, 1_000)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
