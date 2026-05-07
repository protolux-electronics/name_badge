defmodule NameBadge.Screen.CounterTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias NameBadge.Screen
  alias NameBadge.Screen.Counter

  describe "render/1" do
    test "delegates to the adapter (returns the cached PNG from assigns)" do
      png = <<137, 80, 78, 71, 13, 10, 26, 10, "fake">>
      assert Counter.render(%{png: png}) == png
    end
  end

  describe "handle_button/3" do
    test "delegates to the adapter and forwards to the configured key map" do
      screen = %Screen{
        module: Counter,
        assigns: %{
          server: self(),
          key_map: %{
            {:button_1, :single_press} => %Key{code: "up", kind: "press", modifiers: []}
          }
        }
      }

      assert {:noreply, _} = Counter.handle_button(:button_1, :single_press, screen)
      assert_receive {:ex_ratatui_event, %Key{code: "up"}}
    end
  end

  describe "handle_info/2" do
    test "delegates unrelated messages to the adapter (which ignores them)" do
      screen = %Screen{module: Counter, assigns: %{}}

      assert {:noreply, ^screen} = Counter.handle_info(:tick, screen)
    end
  end
end
