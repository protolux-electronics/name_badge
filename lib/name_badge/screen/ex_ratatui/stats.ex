defmodule NameBadge.Screen.ExRatatui.Stats do
  @moduledoc """
  Live BEAM system monitor — the data-driven showcase for
  `NameBadge.Screen.ExRatatui`. Refreshes every 3 seconds through an
  interval subscription and tells a one-glance story of what the VM
  on the badge is actually doing.

  The screen is laid out from top to bottom as a small infographic:

      ┌─ ex_ratatui - stats ────────────────────────┐
      │┌─ summary ─────────────────────────────────┐│
      ││ BEAM live - uptime 3m 12s - processes 312 ││
      │└───────────────────────────────────────────┘│
      │┌─ memory by category ──────────────────────┐│
      ││  proc  ████████████████      8.2 MiB      ││
      ││  bin   ████████              4.1 MiB      ││
      ││  ets   ██                    2.0 MiB      ││
      ││  code  ██                    1.9 MiB      ││
      ││  atom  █                     0.4 MiB      ││
      │└───────────────────────────────────────────┘│
      │┌─ limits ──────────────────────────────────┐│
      ││ processes [██████   ]   312 / 262144      ││
      ││ atoms     [█        ]    14k / 1M         ││
      │└───────────────────────────────────────────┘│
      │┌─ trends ──────────────────────────────────┐│
      ││ memory    ▁▂▃▅▇█▇▅▃▂▁                     ││
      ││ work/sec  ▂▅▃▇█▇▅▃▂▁▂                     ││
      ││ run queue ▁▁▂▁▃▂▁▁▁▂                      ││
      │└───────────────────────────────────────────┘│
      │┌─ top by reductions ───────────────────────┐│
      ││ <0.123.0>  Logger.Backend         1.2M    ││
      ││  …                                        ││
      │└───────────────────────────────────────────┘│
      └─────────────────────────────────────────────┘

       [ A ] pause   [ B ] cycle   [ B long ] back

  Three rolling histories (50 samples ≈ 2.5 minutes) feed the
  sparklines: total memory in KiB, reductions-per-tick (BEAM's unit
  of scheduled work), and the total run-queue length (pending work
  across all schedulers). The five "memory by category" bars come
  from `:erlang.memory/0` and partition the total into the buckets
  that actually matter when sizing a Nerves device. The two gauges
  read out current vs. system-configured limits for processes and
  atoms — both useful "is this VM about to fall over" indicators.

  The 3 s cadence is tuned for the badge's UC8276 partial-refresh
  budget — every tick repaints the bar chart, gauges, sparklines,
  and the top-N panel, and at 3 s the panel keeps up without
  queueing.

  Process metric is user-cyclable: reductions / memory / message
  queue length. The metric drives the bottom "top processes" panel.

  ## Controls

  | Key (TUI) | Badge button     | Action               |
  | --------- | ---------------- | -------------------- |
  | `up`      | A (single press) | Pause/resume refresh |
  | `down`    | B (single press) | Cycle metric         |
  | `home`    | A (long press)   | Reset histories      |
  | —         | B (long press)   | Back to menu         |
  """

  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Subscription
  alias ExRatatui.Widgets.{Block, Paragraph, Sparkline}
  alias NameBadge.ExRatatui.Frame

  @history_len 50
  @top_n 12
  @metrics [:reductions, :memory, :message_queue_len]
  @bar_set [" ", "▄", "█"]
  @refresh_interval_ms 3_000

  # Categories shown in the "memory by category" bar chart, in the
  # order they're stacked top-to-bottom. Keys must exist in the map
  # returned by `:erlang.memory/0`.
  @mem_categories [
    {:processes, "proc"},
    {:binary, "bin "},
    {:ets, "ets "},
    {:code, "code"},
    {:atom, "atom"}
  ]

  @typedoc false
  @type metric :: :reductions | :memory | :message_queue_len

  @typedoc false
  @type sample :: %{
          uptime_ms: non_neg_integer(),
          memory_kib: non_neg_integer(),
          reds_delta: non_neg_integer(),
          procs: non_neg_integer(),
          proc_limit: pos_integer(),
          atom_count: non_neg_integer(),
          atom_limit: pos_integer(),
          queue_len: non_neg_integer(),
          mem_breakdown: %{atom() => non_neg_integer()},
          top: [{pid(), String.t(), non_neg_integer()}]
        }

  @typedoc false
  @type state :: %{
          paused?: boolean(),
          metric: metric(),
          last_reductions: non_neg_integer() | nil,
          memory_history: [non_neg_integer()],
          reds_history: [non_neg_integer()],
          queue_history: [non_neg_integer()],
          sample: sample() | nil
        }

  @impl ExRatatui.App
  def init(_opts) do
    {:ok,
     %{
       paused?: false,
       metric: :reductions,
       last_reductions: nil,
       memory_history: [],
       reds_history: [],
       queue_history: [],
       sample: nil
     }
     |> refresh()}
  end

  @impl ExRatatui.App
  def render(state, frame) do
    {block, block_rect, content_rect, hint_rect} = Frame.layout("stats", frame)
    sample = state.sample || empty_sample()

    # Five inset section blocks tile content_rect top-to-bottom. Each
    # has a 1-cell border on every side, so child widgets get a 2-cell
    # narrower / 2-row shorter content area than the section rect.
    [summary_rect, mem_rect, limits_rect, trends_rect, top_rect] =
      stack_rects(content_rect, [3, 7, 4, 5, 14])

    [
      {block, block_rect},
      {hint_paragraph(state), hint_rect}
    ]
    |> Kernel.++(summary_section(sample, summary_rect))
    |> Kernel.++(memory_section(sample, mem_rect))
    |> Kernel.++(limits_section(sample, limits_rect))
    |> Kernel.++(trends_section(state, trends_rect))
    |> Kernel.++(top_section(sample, state.metric, top_rect))
  end

  @impl ExRatatui.App
  def update({:event, %Key{code: "up"}}, state),
    do: {:noreply, %{state | paused?: not state.paused?}}

  def update({:event, %Key{code: "down"}}, state),
    do: {:noreply, %{state | metric: cycle_metric(state.metric)} |> refresh()}

  def update({:event, %Key{code: "home"}}, state) do
    {:noreply,
     %{state | memory_history: [], reds_history: [], queue_history: [], last_reductions: nil}
     |> refresh()}
  end

  def update({:info, :refresh}, %{paused?: true} = state), do: {:noreply, state}
  def update({:info, :refresh}, state), do: {:noreply, refresh(state)}

  def update(_msg, state), do: {:noreply, state}

  @impl ExRatatui.App
  def subscriptions(_state) do
    [Subscription.interval(:stats_refresh, @refresh_interval_ms, :refresh)]
  end

  # Pure refresh: takes a state, samples the BEAM, returns the new state.
  @doc false
  def refresh(state) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    mem = Map.new(:erlang.memory())
    memory_kib = div(mem.total, 1024)
    {total_reds, _} = :erlang.statistics(:reductions)

    reds_delta =
      case state.last_reductions do
        nil -> 0
        prev -> max(total_reds - prev, 0)
      end

    procs = length(Process.list())
    queue_len = :erlang.statistics(:total_run_queue_lengths)
    top = top_processes(state.metric)

    sample = %{
      uptime_ms: uptime_ms,
      memory_kib: memory_kib,
      reds_delta: reds_delta,
      procs: procs,
      proc_limit: :erlang.system_info(:process_limit),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      queue_len: queue_len,
      mem_breakdown: Map.take(mem, [:processes, :binary, :ets, :code, :atom]),
      top: top
    }

    %{
      state
      | last_reductions: total_reds,
        memory_history: push_history(state.memory_history, memory_kib),
        reds_history: push_history(state.reds_history, reds_delta),
        queue_history: push_history(state.queue_history, queue_len),
        sample: sample
    }
  end

  # Internally newest-first: prepend O(1), truncate via Enum.take.
  # Sparklines render oldest-on-the-left, so callers reverse at read
  # time — see `trends_section/2`.
  defp push_history(history, value) do
    [value | Enum.take(history, @history_len - 1)]
  end

  defp cycle_metric(metric) do
    idx = Enum.find_index(@metrics, &(&1 == metric)) || 0
    Enum.at(@metrics, rem(idx + 1, length(@metrics)))
  end

  defp top_processes(metric) do
    Process.list()
    |> Enum.map(fn pid -> {pid, Process.info(pid, [metric, :registered_name, :initial_call])} end)
    |> Enum.flat_map(fn
      {pid, info} when is_list(info) -> [{pid, info}]
      _ -> []
    end)
    |> Enum.map(fn {pid, info} ->
      value = Keyword.get(info, metric, 0)
      label = process_label(info)
      {pid, label, value}
    end)
    |> Enum.sort_by(fn {_pid, _label, value} -> value end, :desc)
    |> Enum.take(@top_n)
  end

  defp process_label(info) do
    case Keyword.get(info, :registered_name) do
      [] ->
        case Keyword.get(info, :initial_call) do
          {mod, fun, arity} -> "#{inspect(mod)}.#{fun}/#{arity}"
          _ -> "—"
        end

      name when is_atom(name) ->
        Atom.to_string(name)
    end
  end

  # ── Section builders ───────────────────────────────────────────────
  #
  # Each section paints its own titled `Block` over a rect carved out
  # of the outer Frame's content area, then layers child widgets
  # on top of the block's hollow interior. Order matters: section
  # blocks come first, content widgets after, so the borders never
  # paint over the content.

  defp summary_section(sample, rect) do
    inner = inner_rect(rect)

    text =
      "BEAM live - uptime " <>
        format_uptime(sample.uptime_ms) <> " - processes " <> Integer.to_string(sample.procs)

    [
      {%Block{title: " summary ", borders: [:all]}, rect},
      {%Paragraph{text: text}, %Rect{x: inner.x, y: inner.y, width: inner.width, height: 1}}
    ]
  end

  defp memory_section(sample, rect) do
    inner = inner_rect(rect)
    breakdown = sample.mem_breakdown || %{}
    max_value = breakdown |> Map.values() |> Enum.max(fn -> 1 end) |> max(1)

    label_w = 6
    value_w = 10
    bar_w = max(inner.width - label_w - value_w - 1, 1)

    rows =
      @mem_categories
      |> Enum.with_index()
      |> Enum.map(fn {{key, label}, idx} ->
        bytes = Map.get(breakdown, key, 0)
        fill = round(bytes / max_value * bar_w)
        bar = String.duplicate("█", fill) <> String.duplicate(" ", bar_w - fill)
        value = format_kib(div(bytes, 1024))

        text =
          " " <>
            String.pad_trailing(label, label_w - 1) <>
            bar <> " " <> String.pad_leading(value, value_w)

        {%Paragraph{text: text},
         %Rect{x: inner.x, y: inner.y + idx, width: inner.width, height: 1}}
      end)

    [{%Block{title: " memory by category ", borders: [:all]}, rect} | rows]
  end

  defp limits_section(sample, rect) do
    inner = inner_rect(rect)

    [
      {%Block{title: " limits ", borders: [:all]}, rect},
      gauge_row("processes", sample.procs, sample.proc_limit, inner.x, inner.width, inner.y),
      gauge_row(
        "atoms    ",
        sample.atom_count,
        sample.atom_limit,
        inner.x,
        inner.width,
        inner.y + 1
      )
    ]
  end

  defp gauge_row(label, value, limit, x, w, y) do
    label_w = 11
    suffix = "  " <> format_count(value) <> " / " <> format_count(limit)
    suffix_w = byte_size(suffix)
    bar_w = max(w - label_w - suffix_w - 2, 1)

    ratio = if limit > 0, do: min(value / limit, 1.0), else: 0.0
    fill = round(ratio * bar_w)
    bar = "[" <> String.duplicate("█", fill) <> String.duplicate(" ", bar_w - fill) <> "]"

    text = String.pad_trailing(label, label_w) <> bar <> suffix
    {%Paragraph{text: text}, %Rect{x: x, y: y, width: w, height: 1}}
  end

  defp trends_section(state, rect) do
    inner = inner_rect(rect)
    label_w = 10
    spark_x = inner.x + label_w
    spark_w = inner.width - label_w

    sparkline_rows = [
      {"memory   ", state.memory_history, 0},
      {"work/sec ", state.reds_history, 1},
      {"run queue", state.queue_history, 2}
    ]

    rows =
      Enum.flat_map(sparkline_rows, fn {label, data, dy} ->
        [
          {%Paragraph{text: label},
           %Rect{x: inner.x, y: inner.y + dy, width: label_w, height: 1}},
          {%Sparkline{data: Enum.reverse(data), bar_set: @bar_set},
           %Rect{x: spark_x, y: inner.y + dy, width: spark_w, height: 1}}
        ]
      end)

    [{%Block{title: " trends ", borders: [:all]}, rect} | rows]
  end

  defp top_section(sample, metric, rect) do
    inner = inner_rect(rect)

    rows =
      sample.top
      |> Enum.take(inner.height)
      |> Enum.with_index()
      |> Enum.map(fn {{pid, label, value}, idx} ->
        {%Paragraph{text: format_top_line(pid, label, value, metric, inner.width)},
         %Rect{x: inner.x, y: inner.y + idx, width: inner.width, height: 1}}
      end)

    [{%Block{title: " top by #{Atom.to_string(metric)} ", borders: [:all]}, rect} | rows]
  end

  # Carve a list of stacked rects out of the parent, top-to-bottom,
  # one per height in `heights`. No gap rows — sections share borders
  # (each section draws its own full perimeter so adjacent sections
  # produce a doubled horizontal line, which reads as a divider).
  defp stack_rects(%Rect{x: x, y: y, width: w}, heights) do
    {rects, _} =
      Enum.map_reduce(heights, y, fn h, cursor ->
        {%Rect{x: x, y: cursor, width: w, height: h}, cursor + h}
      end)

    rects
  end

  # Shrink a rect by 1 cell on every side — the content area inside a
  # full-bordered Block.
  defp inner_rect(%Rect{x: x, y: y, width: w, height: h}) do
    %Rect{x: x + 1, y: y + 1, width: w - 2, height: h - 2}
  end

  # ── Formatting helpers ────────────────────────────────────────────

  defp format_top_line(pid, label, value, metric, width) do
    pid_str = inspect(pid)
    value_str = format_metric(metric, value)
    pad = max(width - byte_size(pid_str) - byte_size(value_str) - 2, 1)

    truncated_label = String.slice(label, 0, pad)
    pad_spaces = String.duplicate(" ", max(pad - byte_size(truncated_label), 1))

    pid_str <> " " <> truncated_label <> pad_spaces <> value_str
  end

  defp format_metric(:memory, bytes), do: format_kib(div(bytes, 1024))
  defp format_metric(_metric, value), do: format_count(value)

  defp format_uptime(ms) do
    seconds = div(ms, 1000)
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)

    cond do
      h > 0 -> "#{h}h #{m}m #{s}s"
      m > 0 -> "#{m}m #{s}s"
      true -> "#{s}s"
    end
  end

  defp format_kib(kib) when kib >= 1024,
    do: :erlang.float_to_binary(kib / 1024, decimals: 1) <> " MiB"

  defp format_kib(kib), do: "#{kib} KiB"

  defp format_count(n) when n >= 1_000_000,
    do: :erlang.float_to_binary(n / 1_000_000, decimals: 1) <> "M"

  defp format_count(n) when n >= 1_000,
    do: :erlang.float_to_binary(n / 1_000, decimals: 1) <> "K"

  defp format_count(n), do: Integer.to_string(n)

  defp empty_sample do
    %{
      uptime_ms: 0,
      memory_kib: 0,
      reds_delta: 0,
      procs: 0,
      proc_limit: 1,
      atom_count: 0,
      atom_limit: 1,
      queue_len: 0,
      mem_breakdown: %{processes: 0, binary: 0, ets: 0, code: 0, atom: 0},
      top: []
    }
  end

  defp hint_paragraph(state) do
    pause_label = if state.paused?, do: " resume   ", else: " pause    "

    Frame.hint([
      {" A ", :chip},
      {pause_label, :label},
      {" B ", :chip},
      {" cycle    ", :label},
      {" B long ", :chip},
      {" back", :label}
    ])
  end
end
