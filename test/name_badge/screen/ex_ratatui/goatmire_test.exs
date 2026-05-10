defmodule NameBadge.Screen.ExRatatui.GoatmireTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Canvas, Paragraph}
  alias ExRatatui.Widgets.Canvas.Points
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

    test "A long (home) snaps the goat back to the rest frame by zeroing tick" do
      assert {:noreply, %{tick: 0, paused?: false}} =
               Goatmire.update({:event, key("home")}, %{tick: 99, paused?: false})

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
    test "registers a hardware-friendly tick subscription with a stable id" do
      assert [
               %Subscription{
                 id: :goat_tick,
                 kind: :interval,
                 interval_ms: interval,
                 message: :tick
               }
             ] = Goatmire.subscriptions(%{tick: 0, paused?: false})

      # Tick must clear the badge's UC8276 partial-refresh budget
      # (≈ 350 ms) with margin so frames don't queue on hardware.
      assert interval >= 700
    end
  end

  describe "ascii_to_points/3" do
    test "emits one coordinate per non-space character, with row 0 at y_origin" do
      art = """
        ##
       ###
      """

      %Points{coords: coords, color: :white} = Goatmire.ascii_to_points(art, 0.0, 10.0)

      # 5 non-space chars (`##` then `###`).
      assert length(coords) == 5

      # Row 0 ("  ##") sits on y_origin = 10.0; row 1 ("###") sits at 9.0.
      ys = Enum.map(coords, fn {_x, y} -> y end) |> Enum.uniq() |> Enum.sort()
      assert ys == [9.0, 10.0]

      # Spaces don't emit pixels — row 1 is " ###", so the leading
      # column is absent and we get coords at x = 1, 2, 3.
      row_1_xs = for {x, 9.0} <- coords, do: x
      assert row_1_xs == [1.0, 2.0, 3.0]
    end

    test "respects the x and y origins" do
      %Points{coords: [{x, y}]} = Goatmire.ascii_to_points("#", 7.5, 3.0)
      assert {x, y} == {7.5, 3.0}
    end
  end

  describe "render/2" do
    setup do
      [widgets: Goatmire.render(%{tick: 0, paused?: false}, frame())]
    end

    test "produces a bordered canvas plus a hint paragraph", %{widgets: widgets} do
      assert length(widgets) == 2

      [{canvas, canvas_rect}, {hint, hint_rect}] = widgets

      assert %Canvas{
               marker: :block,
               block: %Block{title: " ex_ratatui · goatmire ", borders: [:all]}
             } = canvas

      assert %Paragraph{text: spans} = hint
      assert is_list(spans)

      # Canvas owns the screen above the hint row.
      assert canvas_rect.height == frame().height - 2
      assert hint_rect.y == frame().height - 1
    end

    test "the goat renders as a Points shape with many ink cells", %{widgets: widgets} do
      [{%Canvas{shapes: shapes}, _}, _] = widgets

      points = Enum.find(shapes, &match?(%Points{}, &1))
      assert %Points{coords: coords} = points
      # The pixel-art goat is a substantial silhouette; if it ever
      # drops below this, something has gone wrong with the helper or
      # the heredoc trimming.
      assert length(coords) > 50
    end

    test "frames alternate between successive ticks (animation alive)" do
      [{%Canvas{shapes: shapes_a}, _}, _] = Goatmire.render(%{tick: 0, paused?: false}, frame())
      [{%Canvas{shapes: shapes_b}, _}, _] = Goatmire.render(%{tick: 1, paused?: false}, frame())

      coords_a = shapes_a |> points_coords() |> MapSet.new()
      coords_b = shapes_b |> points_coords() |> MapSet.new()

      refute MapSet.equal?(coords_a, coords_b)
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

  defp points_coords(shapes) do
    shapes
    |> Enum.find(&match?(%Points{}, &1))
    |> Map.get(:coords)
  end
end
