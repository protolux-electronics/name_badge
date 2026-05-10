defmodule NameBadge.Screen.ExRatatui.GoatmireTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Canvas, Paragraph}
  alias ExRatatui.Widgets.Canvas.{Line, Points, Rectangle}
  alias NameBadge.Screen.ExRatatui.Goatmire

  describe "init/1" do
    test "starts at tick 0 and unpaused" do
      assert {:ok, %{tick: 0, paused?: false}} = Goatmire.init([])
    end
  end

  describe "update/2 — events" do
    test "A (up) toggles paused?" do
      assert {:noreply, %{paused?: true}} =
               Goatmire.update({:event, key("up")}, %{tick: 7, paused?: false})

      assert {:noreply, %{paused?: false}} =
               Goatmire.update({:event, key("up")}, %{tick: 7, paused?: true})
    end

    test "A long (home) snaps the tail back to rest by zeroing tick" do
      assert {:noreply, %{tick: 0, paused?: false}} =
               Goatmire.update({:event, key("home")}, %{tick: 99, paused?: false})

      # Reset is independent of paused state.
      assert {:noreply, %{tick: 0, paused?: true}} =
               Goatmire.update({:event, key("home")}, %{tick: 99, paused?: true})
    end

    test "ignores unmapped keys" do
      state = %{tick: 5, paused?: false}
      assert {:noreply, ^state} = Goatmire.update({:event, key("down")}, state)
      assert {:noreply, ^state} = Goatmire.update({:event, key("q")}, state)
    end
  end

  describe "update/2 — ticks" do
    test "tick advances when not paused" do
      assert {:noreply, %{tick: 1}} =
               Goatmire.update({:info, :tick}, %{tick: 0, paused?: false})

      assert {:noreply, %{tick: 43}} =
               Goatmire.update({:info, :tick}, %{tick: 42, paused?: false})
    end

    test "tick is a no-op when paused" do
      assert {:noreply, %{tick: 42}} =
               Goatmire.update({:info, :tick}, %{tick: 42, paused?: true})
    end

    test "ignores unrelated info messages" do
      state = %{tick: 1, paused?: false}
      assert {:noreply, ^state} = Goatmire.update({:info, :unrelated}, state)
    end
  end

  describe "subscriptions/1" do
    test "registers a 250 ms tick subscription with a stable id" do
      assert [%Subscription{id: :goat_tick, kind: :interval, interval_ms: 250, message: :tick}] =
               Goatmire.subscriptions(%{tick: 0, paused?: false})
    end
  end

  describe "render/2" do
    setup do
      [widgets: Goatmire.render(%{tick: 4, paused?: false}, frame())]
    end

    test "produces a bordered canvas plus a hint paragraph", %{widgets: widgets} do
      assert length(widgets) == 2

      [{canvas, canvas_rect}, {hint, hint_rect}] = widgets

      assert %Canvas{
               marker: :block,
               block: %Block{title: " hi from ex_ratatui ", borders: [:all]}
             } = canvas

      assert %Paragraph{text: spans} = hint
      assert is_list(spans)

      # Canvas takes everything but the bottom hint row.
      assert canvas_rect.height == frame().height - 2
      assert hint_rect.y == frame().height - 1
    end

    test "canvas carries the goat's static parts and the animated tail", %{widgets: widgets} do
      [{%Canvas{shapes: shapes}, _}, _] = widgets

      assert %Rectangle{x: -12.0, width: 14.0} =
               Enum.find(shapes, &match?(%Rectangle{x: -12.0}, &1))

      assert %Rectangle{x: 2.0, width: 8.0} = Enum.find(shapes, &match?(%Rectangle{x: 2.0}, &1))

      assert Enum.any?(shapes, &match?(%Points{coords: [{8.0, 6.0}]}, &1))

      # 2 horns + 4 legs + 1 beard + 1 tail = 8 lines on the canvas.
      lines = Enum.filter(shapes, &match?(%Line{}, &1))
      assert length(lines) == 8
    end

    test "tail tip moves between successive ticks (animation alive)" do
      [{%Canvas{shapes: shapes_a}, _}, _] = Goatmire.render(%{tick: 0, paused?: false}, frame())
      [{%Canvas{shapes: shapes_b}, _}, _] = Goatmire.render(%{tick: 3, paused?: false}, frame())

      tail_a = tail_line(shapes_a)
      tail_b = tail_line(shapes_b)

      # Tail base is fixed; tip should differ across ticks because of
      # the sin(tick * step) factor.
      assert {tail_a.x1, tail_a.y1} == {-12.0, 5.0}
      assert {tail_b.x1, tail_b.y1} == {-12.0, 5.0}
      refute {tail_a.x2, tail_a.y2} == {tail_b.x2, tail_b.y2}
    end

    test "hint reflects pause state" do
      [_, {%Paragraph{text: spans_running}, _}] =
        Goatmire.render(%{tick: 0, paused?: false}, frame())

      [_, {%Paragraph{text: spans_paused}, _}] =
        Goatmire.render(%{tick: 0, paused?: true}, frame())

      assert spans_running |> Enum.map(& &1.content) |> Enum.join() =~ "pause"
      assert spans_paused |> Enum.map(& &1.content) |> Enum.join() =~ "resume"
    end

    test "key chips render in reverse-video", %{widgets: widgets} do
      [_, {%Paragraph{text: spans}, _}] = widgets

      reversed = %Style{modifiers: [:reversed]}
      assert %Span{content: " A ", style: ^reversed} = Enum.at(spans, 0)
      assert %Span{content: " A long ", style: ^reversed} = Enum.at(spans, 2)
      assert %Span{content: " B long ", style: ^reversed} = Enum.at(spans, 4)
    end

    test "every rect fits within the frame" do
      widgets = Goatmire.render(%{tick: 0, paused?: false}, frame())

      for {_widget, rect} <- widgets do
        assert rect.x + rect.width <= frame().width
        assert rect.y + rect.height <= frame().height
      end
    end
  end

  defp frame, do: %Rect{x: 0, y: 0, width: 66, height: 37}
  defp key(code), do: %Key{code: code, kind: "press", modifiers: []}

  defp tail_line(shapes) do
    Enum.find(shapes, fn
      %Line{x1: -12.0, y1: 5.0} -> true
      _ -> false
    end)
  end
end
