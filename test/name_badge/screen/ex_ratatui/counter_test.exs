defmodule NameBadge.Screen.ExRatatui.CounterTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Paragraph}
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

    test "down decrements" do
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
    setup do
      [widgets: Counter.render(%{count: 7}, frame())]
    end

    test "produces the shared chrome plus a centered count and a single hint row", %{
      widgets: widgets
    } do
      assert length(widgets) == 3

      [{block, block_rect}, {count, count_rect}, {hint, hint_rect}] = widgets

      assert %Block{title: " ex_ratatui · counter ", borders: [:all]} = block
      assert %Paragraph{text: "count: 7", alignment: :center} = count
      assert %Paragraph{text: spans} = hint
      assert is_list(spans)

      # Block fills everything but the bottom hint row.
      assert block_rect.height == frame().height - 2
      # Count is roughly vertically centered in the inner content
      # area (block borders take 1 cell on each side, so content
      # height is frame().height - 4).
      assert count_rect.y > div(frame().height, 3)
      assert count_rect.y < frame().height - 4
      # Hint sits on the very bottom row.
      assert hint_rect.y == frame().height - 1
    end

    test "key chips render in reverse-video and action labels are plain", %{widgets: widgets} do
      [_, _, {%Paragraph{text: spans}, _}] = widgets

      reversed = %Style{modifiers: [:reversed]}

      # Chips at even positions (0, 2, 4, 6); labels at odd positions
      # (1, 3, 5, 7).
      assert %Span{content: " A ", style: ^reversed} = Enum.at(spans, 0)
      assert %Span{content: " A long ", style: ^reversed} = Enum.at(spans, 2)
      assert %Span{content: " B ", style: ^reversed} = Enum.at(spans, 4)
      assert %Span{content: " B long ", style: ^reversed} = Enum.at(spans, 6)

      for span_index <- [1, 3, 5, 7] do
        assert %Span{style: %Style{modifiers: []}} = Enum.at(spans, span_index)
      end
    end

    test "every rect fits within the frame" do
      widgets = Counter.render(%{count: 0}, frame())

      for {_widget, rect} <- widgets do
        assert rect.x + rect.width <= frame().width
        assert rect.y + rect.height <= frame().height
      end
    end
  end

  defp frame, do: %Rect{x: 0, y: 0, width: 66, height: 37}
  defp key(code), do: %Key{code: code, kind: "press", modifiers: []}
end
