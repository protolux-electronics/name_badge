defmodule NameBadge.Screen.ExRatatui.Stats do
  @moduledoc """
  Live BEAM system monitor — the data-driven showcase for
  `NameBadge.Screen.ExRatatui`. Refreshes every 3 seconds through an
  interval subscription, keeps a rolling 50-sample history of memory
  and reduction throughput (≈ 2.5 minutes), and renders both as
  `Sparkline`s using a three-level bar set (`" "`, `"▄"`, `"█"`) that
  the badge font ships glyphs for.

  The 3 s cadence is tuned for the badge's UC8276 partial-refresh
  budget — every tick produces a new frame for memory, reductions,
  and the top-N panel, and at 3 s the panel keeps up without queueing.

  Process metric is user-cyclable: reductions / memory / message
  queue length. The metric drives the bottom "top processes" panel.

  ## Layout

      ┌─ system ────────────────────────────────────┐
      │  uptime: …      procs: …                    │
      │  memory: …      reds/s: …                   │
      │  memory  ▁▂▃▅▇█▇▅▃▂▁                        │
      │  reds/s  ▂▅▃▇█▇▅▃▂▁▂                        │
      │  ── top by reductions ──                    │
      │  <0.123.0>  Logger.Backend         1.2M     │
      └─────────────────────────────────────────────┘

       [ A ] pause   [ B ] cycle   [ B long ] back

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
  alias ExRatatui.Widgets.{Paragraph, Sparkline}
  alias NameBadge.ExRatatui.DemoFrame

  @history_len 50
  @top_n 10
  @metrics [:reductions, :memory, :message_queue_len]
  @bar_set [" ", "▄", "█"]
  @refresh_interval_ms 3_000

  @typedoc false
  @type metric :: :reductions | :memory | :message_queue_len

  @typedoc false
  @type sample :: %{
          uptime_ms: non_neg_integer(),
          memory_kib: non_neg_integer(),
          reds_delta: non_neg_integer(),
          procs: non_neg_integer(),
          top: [{pid(), String.t(), non_neg_integer()}]
        }

  @typedoc false
  @type state :: %{
          paused?: boolean(),
          metric: metric(),
          last_reductions: non_neg_integer() | nil,
          memory_history: [non_neg_integer()],
          reds_history: [non_neg_integer()],
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
       sample: nil
     }
     |> refresh()}
  end

  @impl ExRatatui.App
  def render(state, frame) do
    {block, block_rect, content_rect, hint_rect} = DemoFrame.layout("stats", frame)
    sample = state.sample || empty_sample()

    # Lay the content out on a row grid that breathes — pad blank
    # rows between sections so the screen doesn't bunch at the top.
    inner_x = content_rect.x + 1
    inner_w = content_rect.width - 2
    label_w = 8

    summary = [
      {0, "uptime: #{format_uptime(sample.uptime_ms)}    procs: #{sample.procs}"},
      {1,
       "memory: #{format_kib(sample.memory_kib)}    reds/s: #{format_count(sample.reds_delta)}"}
    ]

    summary_widgets =
      for {dy, text} <- summary do
        {%Paragraph{text: text},
         %Rect{x: inner_x, y: content_rect.y + dy, width: inner_w, height: 1}}
      end

    sparkline_y = content_rect.y + 3

    sparkline_widgets = [
      {%Paragraph{text: "memory"}, %Rect{x: inner_x, y: sparkline_y, width: label_w, height: 1}},
      {%Sparkline{data: state.memory_history, bar_set: @bar_set},
       %Rect{
         x: inner_x + label_w,
         y: sparkline_y,
         width: inner_w - label_w,
         height: 1
       }},
      {%Paragraph{text: "reds/s"},
       %Rect{x: inner_x, y: sparkline_y + 2, width: label_w, height: 1}},
      {%Sparkline{data: state.reds_history, bar_set: @bar_set},
       %Rect{
         x: inner_x + label_w,
         y: sparkline_y + 2,
         width: inner_w - label_w,
         height: 1
       }}
    ]

    top_header_y = sparkline_y + 4

    top_widgets = [
      {%Paragraph{text: "── top by #{Atom.to_string(state.metric)} ──"},
       %Rect{x: inner_x, y: top_header_y, width: inner_w, height: 1}}
      | sample.top
        |> Enum.with_index()
        |> Enum.map(fn {{pid, label, value}, idx} ->
          {%Paragraph{text: format_top_line(pid, label, value, state.metric, inner_w)},
           %Rect{x: inner_x, y: top_header_y + 1 + idx, width: inner_w, height: 1}}
        end)
    ]

    [{block, block_rect}, {hint_paragraph(state), hint_rect}]
    |> Kernel.++(summary_widgets)
    |> Kernel.++(sparkline_widgets)
    |> Kernel.++(top_widgets)
  end

  @impl ExRatatui.App
  def update({:event, %Key{code: "up"}}, state),
    do: {:noreply, %{state | paused?: not state.paused?}}

  def update({:event, %Key{code: "down"}}, state),
    do: {:noreply, %{state | metric: cycle_metric(state.metric)} |> refresh()}

  def update({:event, %Key{code: "home"}}, state) do
    {:noreply, %{state | memory_history: [], reds_history: [], last_reductions: nil} |> refresh()}
  end

  def update({:info, :refresh}, %{paused?: true} = state), do: {:noreply, state}
  def update({:info, :refresh}, state), do: {:noreply, refresh(state)}

  def update(_msg, state), do: {:noreply, state}

  @impl ExRatatui.App
  def subscriptions(_state) do
    [Subscription.interval(:stats_refresh, @refresh_interval_ms, :refresh)]
  end

  # Pure refresh: takes a state, samples the BEAM, returns the new state.
  # Public-ish (defp) but the test reaches in to drive it deterministically.
  @doc false
  def refresh(state) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    memory_kib = div(:erlang.memory(:total), 1024)
    {total_reds, _} = :erlang.statistics(:reductions)

    reds_delta =
      case state.last_reductions do
        nil -> 0
        prev -> max(total_reds - prev, 0)
      end

    procs = length(Process.list())
    top = top_processes(state.metric)

    sample = %{
      uptime_ms: uptime_ms,
      memory_kib: memory_kib,
      reds_delta: reds_delta,
      procs: procs,
      top: top
    }

    %{
      state
      | last_reductions: total_reds,
        memory_history: push_history(state.memory_history, memory_kib),
        reds_history: push_history(state.reds_history, reds_delta),
        sample: sample
    }
  end

  defp push_history(history, value) do
    history
    |> Enum.take(@history_len - 1)
    |> List.insert_at(-1, value)
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

  defp empty_sample,
    do: %{uptime_ms: 0, memory_kib: 0, reds_delta: 0, procs: 0, top: []}

  defp hint_paragraph(state) do
    pause_label = if state.paused?, do: " resume   ", else: " pause    "

    DemoFrame.hint([
      {" A ", :chip},
      {pause_label, :label},
      {" B ", :chip},
      {" cycle    ", :label},
      {" B long ", :chip},
      {" back", :label}
    ])
  end
end
