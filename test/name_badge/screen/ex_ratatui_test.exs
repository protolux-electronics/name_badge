defmodule NameBadge.Screen.ExRatatuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.CellSession.{Cell, Diff}
  alias ExRatatui.Event.Key
  alias NameBadge.ExRatatui.Raster
  alias NameBadge.Screen
  alias NameBadge.Screen.ExRatatui, as: Adapter

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
end
