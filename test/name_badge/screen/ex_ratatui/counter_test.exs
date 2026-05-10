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
    setup do
      [widgets: Counter.render(%{count: 7}, %Rect{x: 0, y: 0, width: 66, height: 37})]
    end

    test "produces a bordered block, count display, and two hint lines", %{widgets: widgets} do
      assert length(widgets) == 4

      [{block, _}, {count, _}, {a_hints, _}, {b_hints, _}] = widgets

      assert %Block{title: " ex_ratatui · counter ", borders: [:all]} = block
      assert %Paragraph{text: "count: 7", alignment: :center} = count
      assert %Paragraph{text: a_spans} = a_hints
      assert %Paragraph{text: b_spans} = b_hints

      assert is_list(a_spans)
      assert is_list(b_spans)
    end

    test "keys A, A long, B, B long render in reverse-video chips", %{widgets: widgets} do
      [_block, _count, {%Paragraph{text: a_spans}, _}, {%Paragraph{text: b_spans}, _}] = widgets

      reversed = %Style{modifiers: [:reversed]}

      # First and third spans on each hint line are the key chips —
      # they must carry :reversed so the rasterer flips them to
      # paper-on-ink.
      assert %Span{content: " A ", style: ^reversed} = Enum.at(a_spans, 0)
      assert %Span{content: " A long ", style: ^reversed} = Enum.at(a_spans, 2)
      assert %Span{content: " B ", style: ^reversed} = Enum.at(b_spans, 0)
      assert %Span{content: " B long ", style: ^reversed} = Enum.at(b_spans, 2)

      # Action labels are plain (no reversal).
      for span_index <- [1, 3], spans <- [a_spans, b_spans] do
        assert %Span{style: %Style{modifiers: []}} = Enum.at(spans, span_index)
      end
    end

    test "lowercase action labels exercise the new font glyphs", %{widgets: widgets} do
      [
        _block,
        {%Paragraph{text: count_text}, _},
        {%Paragraph{text: a_spans}, _},
        {%Paragraph{text: b_spans}, _}
      ] = widgets

      # The whole string is lowercase except the literal A / B key
      # labels — proves we're not falling back to all-uppercase
      # because of font gaps.
      assert count_text =~ "count:"

      labels =
        (a_spans ++ b_spans)
        |> Enum.map(& &1.content)
        |> Enum.join("")

      assert labels =~ "reset"
      assert labels =~ "back"
    end

    test "every rect fits within the frame" do
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
