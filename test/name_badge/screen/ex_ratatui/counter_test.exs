defmodule NameBadge.Screen.ExRatatui.CounterTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph
  alias NameBadge.Screen.ExRatatui.Counter

  describe "mount/1" do
    test "starts at count 0" do
      assert {:ok, %{count: 0}} = Counter.mount([])
    end
  end

  describe "handle_event/2" do
    test "up increments" do
      assert {:noreply, %{count: 1}} = Counter.handle_event(key("up"), %{count: 0})
      assert {:noreply, %{count: 6}} = Counter.handle_event(key("up"), %{count: 5})
    end

    test "down decrements (no floor — negative counts are allowed)" do
      assert {:noreply, %{count: 4}} = Counter.handle_event(key("down"), %{count: 5})
      assert {:noreply, %{count: -1}} = Counter.handle_event(key("down"), %{count: 0})
    end

    test "home resets to 0 from any value" do
      assert {:noreply, %{count: 0}} = Counter.handle_event(key("home"), %{count: 42})
      assert {:noreply, %{count: 0}} = Counter.handle_event(key("home"), %{count: -7})
    end

    test "ignores unmapped keys" do
      state = %{count: 3}
      assert {:noreply, ^state} = Counter.handle_event(key("left"), state)
      assert {:noreply, ^state} = Counter.handle_event(key("q"), state)
    end
  end

  describe "render/2" do
    test "produces a header, count line, and two footer hints" do
      widgets = Counter.render(%{count: 7}, %Rect{x: 0, y: 0, width: 66, height: 37})

      assert length(widgets) == 4

      texts =
        Enum.map(widgets, fn {%Paragraph{text: text}, _rect} -> text end)

      assert "COUNTER" in texts
      assert "COUNT: 7" in texts
      assert "A: +1    A LONG: RESET" in texts
      assert "B: -1    B LONG: BACK" in texts
    end

    test "every widget is centered horizontally" do
      widgets = Counter.render(%{count: 0}, %Rect{x: 0, y: 0, width: 66, height: 37})

      for {%Paragraph{alignment: alignment}, _rect} <- widgets do
        assert alignment == :center
      end
    end

    test "rects fit within the frame" do
      frame = %Rect{x: 0, y: 0, width: 66, height: 37}
      widgets = Counter.render(%{count: 0}, frame)

      for {_widget, rect} <- widgets do
        assert rect.x + rect.width <= frame.width
        assert rect.y + rect.height <= frame.height
      end
    end
  end

  defp key(code), do: %Key{code: code, kind: "press", modifiers: []}
end
