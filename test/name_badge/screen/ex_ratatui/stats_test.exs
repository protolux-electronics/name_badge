defmodule NameBadge.Screen.ExRatatui.StatsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Paragraph, Sparkline}
  alias NameBadge.Screen.ExRatatui.Stats

  describe "init/1" do
    test "starts unpaused, on :reductions, and seeds a sample" do
      assert {:ok, state} = Stats.init([])
      assert state.paused? == false
      assert state.metric == :reductions
      assert is_map(state.sample)
      assert is_list(state.memory_history) and length(state.memory_history) == 1
      assert is_list(state.reds_history) and length(state.reds_history) == 1
    end
  end

  describe "update/2 — events" do
    setup do
      {:ok, state} = Stats.init([])
      [state: state]
    end

    test "A (up) toggles pause", %{state: state} do
      assert {:noreply, %{paused?: true}} = Stats.update({:event, key("up")}, state)

      assert {:noreply, %{paused?: false}} =
               Stats.update({:event, key("up")}, %{state | paused?: true})
    end

    test "B (down) cycles metric and re-samples", %{state: state} do
      {:noreply, %{metric: m1}} = Stats.update({:event, key("down")}, state)
      {:noreply, %{metric: m2}} = Stats.update({:event, key("down")}, %{state | metric: m1})
      {:noreply, %{metric: m3}} = Stats.update({:event, key("down")}, %{state | metric: m2})

      assert m1 == :memory
      assert m2 == :message_queue_len
      assert m3 == :reductions
    end

    test "home (A long) clears histories and re-seeds with one fresh sample", %{state: state} do
      state = %{
        state
        | memory_history: [10, 20, 30],
          reds_history: [1, 2, 3],
          last_reductions: 999_999
      }

      {:noreply, after_reset} = Stats.update({:event, key("home")}, state)

      assert length(after_reset.memory_history) == 1
      assert length(after_reset.reds_history) == 1
      # last_reductions was reset to nil before refresh ran, so the
      # delta on the seeded sample is zero.
      assert hd(after_reset.reds_history) == 0
    end

    test "ignores unmapped keys", %{state: state} do
      assert {:noreply, ^state} = Stats.update({:event, key("left")}, state)
    end
  end

  describe "update/2 — refresh ticks" do
    setup do
      {:ok, state} = Stats.init([])
      [state: state]
    end

    test "appends a new sample to both histories", %{state: state} do
      assert {:noreply, after_tick} = Stats.update({:info, :refresh}, state)

      assert length(after_tick.memory_history) == length(state.memory_history) + 1
      assert length(after_tick.reds_history) == length(state.reds_history) + 1
    end

    test "is a no-op when paused", %{state: state} do
      paused = %{state | paused?: true}
      assert {:noreply, ^paused} = Stats.update({:info, :refresh}, paused)
    end

    test "history is capped at 50 samples", %{state: state} do
      saturated =
        Enum.reduce(1..60, state, fn _, acc ->
          {:noreply, next} = Stats.update({:info, :refresh}, acc)
          next
        end)

      assert length(saturated.memory_history) == 50
      assert length(saturated.reds_history) == 50
    end

    test "ignores unrelated info messages", %{state: state} do
      assert {:noreply, ^state} = Stats.update({:info, :nope}, state)
    end
  end

  describe "subscriptions/1" do
    test "registers a 1 s refresh subscription with a stable id" do
      assert [
               %Subscription{
                 id: :stats_refresh,
                 kind: :interval,
                 interval_ms: 1_000,
                 message: :refresh
               }
             ] = Stats.subscriptions(%{})
    end
  end

  describe "render/2" do
    setup do
      {:ok, state} = Stats.init([])
      [state: state, widgets: Stats.render(state, frame())]
    end

    test "produces the bordered system block, two stat lines, two sparklines, top header, hint, and top rows",
         %{widgets: widgets} do
      # 1 block + 1 top-header + 1 hint + 2 stat rows + 4 sparkline-related (2 labels + 2 charts) + N top rows.
      block = Enum.find(widgets, &match?({%Block{}, _}, &1))
      assert {%Block{title: " system ", borders: [:all]}, _} = block

      sparklines = Enum.filter(widgets, &match?({%Sparkline{}, _}, &1))
      assert length(sparklines) == 2

      for {%Sparkline{bar_set: bar_set}, _} <- sparklines do
        assert bar_set == [" ", "▄", "█"]
      end
    end

    test "hint shows the cycle action and pause/resume label flips", %{state: state} do
      [_, {%Paragraph{text: spans_running}, _}] =
        widgets_at_hint(Stats.render(state, frame()))

      [_, {%Paragraph{text: spans_paused}, _}] =
        widgets_at_hint(Stats.render(%{state | paused?: true}, frame()))

      assert spans_running |> Enum.map(& &1.content) |> Enum.join() =~ "pause"
      assert spans_paused |> Enum.map(& &1.content) |> Enum.join() =~ "resume"

      reversed = %Style{modifiers: [:reversed]}
      assert %Span{content: " A ", style: ^reversed} = Enum.at(spans_running, 0)
      assert %Span{content: " B ", style: ^reversed} = Enum.at(spans_running, 2)
      assert %Span{content: " B long ", style: ^reversed} = Enum.at(spans_running, 4)
    end

    test "every rect fits within the frame", %{state: state} do
      widgets = Stats.render(state, frame())

      for {_widget, rect} <- widgets do
        assert rect.x + rect.width <= frame().width
        assert rect.y + rect.height <= frame().height
      end
    end
  end

  defp frame, do: %Rect{x: 0, y: 0, width: 66, height: 37}
  defp key(code), do: %Key{code: code, kind: "press", modifiers: []}

  # The hint Paragraph is the one whose rect.y == frame.height - 1.
  defp widgets_at_hint(widgets) do
    {hint_w, hint_r} =
      Enum.find(widgets, fn {_widget, %Rect{y: y}} -> y == frame().height - 1 end)

    [{:hint_marker, nil}, {hint_w, hint_r}]
  end
end
