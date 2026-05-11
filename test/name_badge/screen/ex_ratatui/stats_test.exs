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
      assert is_list(state.queue_history) and length(state.queue_history) == 1
    end

    test "the seeded sample carries memory breakdown and limits" do
      {:ok, state} = Stats.init([])
      sample = state.sample

      # Five categories that partition `:erlang.memory/0` into the
      # buckets the bar chart visualizes.
      assert is_map(sample.mem_breakdown)

      assert Map.keys(sample.mem_breakdown) |> Enum.sort() ==
               [:atom, :binary, :code, :ets, :processes]

      # Limits should always come back as positive integers from the
      # live VM so the gauges have a stable denominator.
      assert sample.proc_limit > 0
      assert sample.atom_limit > 0
      assert sample.atom_count >= 0
      assert sample.queue_len >= 0
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

    test "home (A long) clears all three histories and re-seeds a fresh sample",
         %{state: state} do
      state = %{
        state
        | memory_history: [10, 20, 30],
          reds_history: [1, 2, 3],
          queue_history: [4, 5, 6],
          last_reductions: 999_999
      }

      {:noreply, after_reset} = Stats.update({:event, key("home")}, state)

      assert length(after_reset.memory_history) == 1
      assert length(after_reset.reds_history) == 1
      assert length(after_reset.queue_history) == 1
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
      [state: state, sample: fixture_sample()]
    end

    test ":refresh kicks off an async sample and flips in_flight?", %{state: state} do
      assert {:noreply, after_tick, opts} = Stats.update({:info, :refresh}, state)
      assert after_tick.in_flight? == true
      assert opts[:render?] == false
      assert is_list(opts[:commands]) and opts[:commands] != []
    end

    test ":sample_taken folds into all three histories and resets in_flight?",
         %{state: state, sample: sample} do
      in_flight = %{state | in_flight?: true}

      assert {:noreply, after_fold} = Stats.update({:info, {:sample_taken, sample}}, in_flight)

      assert after_fold.in_flight? == false
      assert length(after_fold.memory_history) == length(state.memory_history) + 1
      assert length(after_fold.reds_history) == length(state.reds_history) + 1
      assert length(after_fold.queue_history) == length(state.queue_history) + 1
    end

    test ":sample_failed resets in_flight? without touching histories", %{state: state} do
      in_flight = %{state | in_flight?: true}

      assert {:noreply, after_fail} = Stats.update({:info, :sample_failed}, in_flight)

      assert after_fail.in_flight? == false
      assert after_fail.memory_history == state.memory_history
      assert after_fail.reds_history == state.reds_history
      assert after_fail.queue_history == state.queue_history
    end

    test "is a no-op when paused", %{state: state} do
      paused = %{state | paused?: true}
      assert {:noreply, ^paused} = Stats.update({:info, :refresh}, paused)
    end

    test "drops :refresh ticks while a sample is still in flight", %{state: state} do
      in_flight = %{state | in_flight?: true}
      assert {:noreply, ^in_flight} = Stats.update({:info, :refresh}, in_flight)
    end

    test ":sample_taken arriving after pause discards the sample but resets in_flight?",
         %{state: state, sample: sample} do
      paused_in_flight = %{state | paused?: true, in_flight?: true}

      assert {:noreply, after_late_sample} =
               Stats.update({:info, {:sample_taken, sample}}, paused_in_flight)

      assert after_late_sample.in_flight? == false
      assert after_late_sample.paused? == true
      assert after_late_sample.memory_history == state.memory_history
      assert after_late_sample.reds_history == state.reds_history
      assert after_late_sample.queue_history == state.queue_history
    end

    test "history is capped at 50 samples", %{state: state, sample: sample} do
      saturated =
        Enum.reduce(1..60, state, fn _, acc ->
          {:noreply, next} = Stats.update({:info, {:sample_taken, sample}}, acc)
          next
        end)

      assert length(saturated.memory_history) == 50
      assert length(saturated.reds_history) == 50
      assert length(saturated.queue_history) == 50
    end

    test "ignores unrelated info messages", %{state: state} do
      assert {:noreply, ^state} = Stats.update({:info, :nope}, state)
    end

    defp fixture_sample do
      %{
        uptime_ms: 1_000,
        memory_kib: 100,
        reds_delta: 50,
        total_reductions: 50,
        procs: 5,
        proc_limit: 262_144,
        atom_count: 100,
        atom_limit: 1_048_576,
        queue_len: 0,
        mem_breakdown: %{processes: 1, binary: 1, ets: 1, code: 1, atom: 1},
        top: []
      }
    end
  end

  describe "subscriptions/1" do
    test "registers a hardware-friendly refresh subscription with a stable id" do
      assert [
               %Subscription{
                 id: :stats_refresh,
                 kind: :interval,
                 interval_ms: interval,
                 message: :refresh
               }
             ] = Stats.subscriptions(%{})

      # Refresh must clear the badge's UC8276 partial-refresh budget
      # (≈ 350 ms) with comfortable margin since each tick repaints
      # the bar chart, gauges, sparklines, and the top-N panel.
      assert interval >= 1_000
    end
  end

  describe "render/2" do
    setup do
      {:ok, state} = Stats.init([])
      [state: state, widgets: Stats.render(state, frame())]
    end

    test "wraps each section in its own titled block on top of the outer chrome",
         %{widgets: widgets} do
      titles = block_titles(widgets)

      # Outer Frame block plus one block per section.
      assert " ex_ratatui - stats " in titles
      assert " summary " in titles
      assert " memory by category " in titles
      assert " limits " in titles
      assert " trends " in titles
      assert Enum.any?(titles, &String.starts_with?(&1, " top by "))

      # Three sparklines: memory, work/sec, run queue.
      sparklines = Enum.filter(widgets, &match?({%Sparkline{}, _}, &1))
      assert length(sparklines) == 3

      for {%Sparkline{bar_set: bar_set}, _} <- sparklines do
        assert bar_set == [" ", "▄", "█"]
      end
    end

    test "summary content reports uptime and process count in plain English",
         %{widgets: widgets} do
      texts = paragraph_texts(widgets)
      assert Enum.any?(texts, &(&1 =~ "BEAM live" and &1 =~ "uptime" and &1 =~ "processes"))
    end

    test "memory section renders one filled bar row per category",
         %{widgets: widgets} do
      texts = paragraph_texts(widgets)

      for label <- ["proc", "bin", "ets", "code", "atom"] do
        assert Enum.any?(texts, &(String.contains?(&1, label) and String.contains?(&1, "█"))),
               "expected a filled bar row for category #{label}"
      end
    end

    test "top-by block title reflects the cycled metric", %{state: state} do
      titles_for = fn metric ->
        Stats.render(%{state | metric: metric}, frame()) |> block_titles()
      end

      assert " top by reductions " in titles_for.(:reductions)
      assert " top by memory " in titles_for.(:memory)
      assert " top by message_queue_len " in titles_for.(:message_queue_len)
    end

    test "gauge rows show value/limit suffixes for processes and atoms",
         %{widgets: widgets} do
      texts = paragraph_texts(widgets)

      assert Enum.any?(texts, fn t ->
               String.starts_with?(t, "processes") and String.contains?(t, " / ") and
                 String.contains?(t, "[")
             end)

      assert Enum.any?(texts, fn t ->
               String.starts_with?(t, "atoms") and String.contains?(t, " / ") and
                 String.contains?(t, "[")
             end)
    end

    test "sparklines are labelled memory / work/sec / run queue",
         %{widgets: widgets} do
      texts = paragraph_texts(widgets)

      for label <- ["memory   ", "work/sec ", "run queue"] do
        assert Enum.any?(texts, &(&1 == label)),
               "expected a sparkline label row for #{inspect(label)}"
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

  defp block_titles(widgets) do
    widgets
    |> Enum.flat_map(fn
      {%Block{title: title}, _} when is_binary(title) -> [title]
      _ -> []
    end)
  end

  defp paragraph_texts(widgets) do
    widgets
    |> Enum.flat_map(fn
      {%Paragraph{text: text}, _} when is_binary(text) -> [text]
      _ -> []
    end)
  end
end
