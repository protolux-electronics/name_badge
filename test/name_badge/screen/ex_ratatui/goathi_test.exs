defmodule NameBadge.Screen.ExRatatui.GoathiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Canvas, Paragraph}
  alias ExRatatui.Widgets.Canvas.Points
  alias NameBadge.Screen.ExRatatui.Goathi

  describe "init/1" do
    test "starts at tick 0 and unpaused" do
      assert {:ok, %{tick: 0, paused?: false}} = Goathi.init([])
    end
  end

  describe "update/2 — events" do
    test "A (up) toggles paused?" do
      assert {:noreply, %{paused?: true}} =
               Goathi.update({:event, key("up")}, %{tick: 7, paused?: false})

      assert {:noreply, %{paused?: false}} =
               Goathi.update({:event, key("up")}, %{tick: 7, paused?: true})
    end

    test "A long (home) snaps the goat back to the rest frame by zeroing tick" do
      assert {:noreply, %{tick: 0, paused?: false}} =
               Goathi.update({:event, key("home")}, %{tick: 99, paused?: false})

      assert {:noreply, %{tick: 0, paused?: true}} =
               Goathi.update({:event, key("home")}, %{tick: 99, paused?: true})
    end

    test "ignores unmapped keys" do
      state = %{tick: 5, paused?: false}
      assert {:noreply, ^state} = Goathi.update({:event, key("down")}, state)
      assert {:noreply, ^state} = Goathi.update({:event, key("q")}, state)
    end
  end

  describe "update/2 — ticks" do
    test "tick advances when not paused" do
      assert {:noreply, %{tick: 1}} =
               Goathi.update({:info, :tick}, %{tick: 0, paused?: false})

      assert {:noreply, %{tick: 43}} =
               Goathi.update({:info, :tick}, %{tick: 42, paused?: false})
    end

    test "tick is a no-op when paused" do
      assert {:noreply, %{tick: 42}} =
               Goathi.update({:info, :tick}, %{tick: 42, paused?: true})
    end

    test "ignores unrelated info messages" do
      state = %{tick: 1, paused?: false}
      assert {:noreply, ^state} = Goathi.update({:info, :unrelated}, state)
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
             ] = Goathi.subscriptions(%{tick: 0, paused?: false})

      # Tick must clear the badge's UC8276 partial-refresh budget
      # (≈ 350 ms) with margin so frames don't queue on hardware.
      assert interval >= 700
    end
  end

  describe "hi_visible?/1" do
    test "blinks on for even ticks, off for odd ticks" do
      assert Goathi.hi_visible?(0)
      refute Goathi.hi_visible?(1)
      assert Goathi.hi_visible?(2)
      refute Goathi.hi_visible?(3)
      assert Goathi.hi_visible?(100)
      refute Goathi.hi_visible?(101)
    end
  end

  describe "ascii_to_points/3" do
    test "emits one coordinate per non-space character, with row 0 at y_origin" do
      art = """
        ##
       ###
      """

      %Points{coords: coords, color: :white} = Goathi.ascii_to_points(art, 0.0, 10.0)

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
      %Points{coords: [{x, y}]} = Goathi.ascii_to_points("#", 7.5, 3.0)
      assert {x, y} == {7.5, 3.0}
    end
  end

  describe "render/2" do
    setup do
      [widgets: Goathi.render(%{tick: 0, paused?: false}, frame())]
    end

    test "produces a bordered canvas plus a hint paragraph", %{widgets: widgets} do
      assert length(widgets) == 2

      [{canvas, canvas_rect}, {hint, hint_rect}] = widgets

      assert %Canvas{
               marker: :block,
               block: %Block{title: " ex_ratatui - goathi ", borders: [:all]}
             } = canvas

      assert %Paragraph{text: spans} = hint
      assert is_list(spans)

      # Canvas owns the screen above the hint row.
      assert canvas_rect.height == frame().height - 2
      assert hint_rect.y == frame().height - 1
    end

    test "the goat renders as a Points shape with many ink cells", %{widgets: widgets} do
      [{%Canvas{shapes: shapes}, _}, _] = widgets

      assert length(shapes) >= 1

      # The goat itself is whichever Points shape has the most ink —
      # the HI! word is the smaller one when it's visible.
      goat = shapes |> Enum.map(& &1.coords) |> Enum.max_by(&length/1)
      # The pixel-art goat is a substantial silhouette; if it ever
      # drops below this, something has gone wrong with the helper or
      # the heredoc trimming.
      assert length(goat) > 50
    end

    test "frames alternate between successive ticks (animation alive)" do
      [{%Canvas{shapes: shapes_a}, _}, _] = Goathi.render(%{tick: 0, paused?: false}, frame())
      [{%Canvas{shapes: shapes_b}, _}, _] = Goathi.render(%{tick: 1, paused?: false}, frame())

      coords_a = shapes_a |> all_coords() |> MapSet.new()
      coords_b = shapes_b |> all_coords() |> MapSet.new()

      refute MapSet.equal?(coords_a, coords_b)
    end

    test "HI! word is present on even ticks and absent on odd ones" do
      [{%Canvas{shapes: shapes_even}, _}, _] =
        Goathi.render(%{tick: 0, paused?: false}, frame())

      [{%Canvas{shapes: shapes_odd}, _}, _] =
        Goathi.render(%{tick: 1, paused?: false}, frame())

      # Two Points shapes when HI! is visible (HI! + goat), one when
      # it's hidden.
      assert length(shapes_even) == 2
      assert length(shapes_odd) == 1
    end

    test "hint reflects pause state" do
      [_, {%Paragraph{text: spans_running}, _}] =
        Goathi.render(%{tick: 0, paused?: false}, frame())

      [_, {%Paragraph{text: spans_paused}, _}] =
        Goathi.render(%{tick: 0, paused?: true}, frame())

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
      widgets = Goathi.render(%{tick: 0, paused?: false}, frame())

      for {_widget, rect} <- widgets do
        assert rect.x + rect.width <= frame().width
        assert rect.y + rect.height <= frame().height
      end
    end
  end

  defp frame, do: %Rect{x: 0, y: 0, width: 66, height: 37}
  defp key(code), do: %Key{code: code, kind: "press", modifiers: []}

  defp all_coords(shapes) do
    Enum.flat_map(shapes, fn %Points{coords: coords} -> coords end)
  end
end
