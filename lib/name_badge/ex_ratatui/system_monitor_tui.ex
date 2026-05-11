defmodule NameBadge.ExRatatui.SystemMonitorTui do
  @moduledoc """
  Three-tab live dashboard of host + BEAM metrics, registered as a
  `nerves_ssh` subsystem so any client with an authorized key can drop
  into a full-color TUI without disturbing the badge's e-ink screen
  (which keeps showing whatever the screen carousel is on).

  Run from a laptop:

      ssh -t nerves@wisteria.local -s Elixir.NameBadge.ExRatatui.SystemMonitorTui

  The `-t` is required — OpenSSH does not allocate a PTY for `-s`
  subsystem mode by default, and without it keystrokes get
  line-buffered locally instead of flowing into the TUI.

  Plain `ssh nerves@wisteria.local` still drops you into the regular
  IEx prompt. From there you can also start the TUI manually:

      iex> NameBadge.ExRatatui.SystemMonitorTui.run()

  Built on the ExRatatui reducer runtime — `init/1` + `update/2` +
  `subscriptions/1`. Heavy `/proc` reads run off the server process
  via `Command.async/2`.

  ## Widgets on display

    * `ExRatatui.Widgets.LineGauge` — RAM and swap as thin line gauges
    * `ExRatatui.Widgets.BarChart` — BEAM memory pool breakdown
    * `ExRatatui.Widgets.Sparkline` — per-scheduler utilization history
    * `ExRatatui.Widgets.Chart` — RAM and load-average time series
    * Rich text via `ExRatatui.Text.{Line, Span}` for colored badges,
      keycaps, and table cells.

  ## Controls

    * `1` / `2` / `3` — switch tabs (Overview / Processes / Graphs)
    * `j` / `Down` — scroll down in the process table
    * `k` / `Up` — scroll up in the process table
    * `q` — quit
  """

  use ExRatatui.App, runtime: :reducer

  require Logger

  alias ExRatatui.{Command, Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.Text.{Line, Span}

  alias ExRatatui.Widgets.{
    Bar,
    BarChart,
    Block,
    Chart,
    LineGauge,
    Paragraph,
    Sparkline,
    Table,
    Tabs
  }

  alias ExRatatui.Widgets.Chart.{Axis, Dataset}
  alias ExRatatui.Widgets.List, as: WList

  @default_refresh_ms 1_000
  @default_top_n 20
  @default_history_size 60

  # -- Reducer callbacks --

  @impl true
  def init(opts) do
    refresh_ms = Keyword.get(opts, :refresh_ms, @default_refresh_ms)
    top_n = Keyword.get(opts, :top_n, @default_top_n)
    history_size = Keyword.get(opts, :history_size, @default_history_size)

    # Enables per-scheduler busy-time accounting (read in
    # `collect_scheduler_usage/1`). Node-global side effect — intentional;
    # leaving it on after this TUI exits is harmless and matches what
    # `:observer` / `observer_cli` do.
    :erlang.system_flag(:scheduler_wall_time, true)

    host = collect_host_info()
    metrics = collect_metrics(nil, top_n)

    state = %{
      tab: 0,
      selected: 0,
      host: host,
      metrics: metrics,
      prev_sched_sample: metrics.sched_sample,
      refresh_ms: refresh_ms,
      top_n: top_n,
      history_size: history_size,
      in_flight?: false,
      ram_history: List.duplicate(0, history_size),
      load_history: List.duplicate({0.0, 0.0, 0.0}, history_size),
      sched_history: List.duplicate(0, history_size)
    }

    {:ok, state}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, tabs_area, body_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:min, 0},
        {:length, 1}
      ])

    body_widgets =
      case state.tab do
        0 -> render_overview(state, body_area)
        1 -> render_processes(state, body_area)
        2 -> render_graphs(state, body_area)
      end

    [
      {header_widget(state), header_area},
      {tabs_widget(state.tab), tabs_area},
      {footer_widget(), footer_area}
      | body_widgets
    ]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}

  def update({:event, %Event.Key{code: "1", kind: "press"}}, state),
    do: {:noreply, %{state | tab: 0}}

  def update({:event, %Event.Key{code: "2", kind: "press"}}, state),
    do: {:noreply, %{state | tab: 1}}

  def update({:event, %Event.Key{code: "3", kind: "press"}}, state),
    do: {:noreply, %{state | tab: 2}}

  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when code in ["j", "Down"] do
    max = length(state.metrics.top_procs) - 1
    {:noreply, %{state | selected: min(state.selected + 1, max)}}
  end

  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when code in ["k", "Up"] do
    {:noreply, %{state | selected: max(state.selected - 1, 0)}}
  end

  def update({:info, :refresh}, %{in_flight?: true} = state) do
    # Previous collection still running. Drop this tick instead of
    # queueing a second async — on the badge under load a heavy
    # collect_metrics (Process.list + per-process info + /proc reads)
    # can occasionally outrun the refresh interval, and queueing would
    # turn a momentary spike into a backlog.
    {:noreply, state, render?: false}
  end

  def update({:info, :refresh}, state) do
    %{prev_sched_sample: prev, top_n: top_n} = state

    cmd =
      Command.async(
        fn -> safe_collect_metrics(prev, top_n) end,
        fn
          :error -> :collect_failed
          metrics -> {:metrics_collected, metrics}
        end
      )

    {:noreply, %{state | in_flight?: true}, commands: [cmd], render?: false}
  end

  def update({:info, :collect_failed}, state) do
    # Strand-prevention: a crashed collect_metrics shouldn't leave
    # `in_flight?` stuck at true and freeze the dashboard. The error
    # itself has already been logged by `safe_collect_metrics/2`.
    {:noreply, %{state | in_flight?: false}, render?: false}
  end

  def update({:info, {:metrics_collected, metrics}}, state) do
    load = metrics.cpu_load
    size = state.history_size

    # Clamp the highlighted row: a high-memory process can disappear
    # between collections, shrinking `top_procs` below the user's
    # current `selected` index. Without this clamp the Table widget
    # would render a highlight on a row that no longer exists.
    selected = min(state.selected, max(length(metrics.top_procs) - 1, 0))

    new_state = %{
      state
      | metrics: metrics,
        prev_sched_sample: metrics.sched_sample,
        selected: selected,
        in_flight?: false,
        ram_history: push_history(state.ram_history, ram_percent(metrics), size),
        load_history:
          push_history(state.load_history, {load.load1, load.load5, load.load15}, size),
        sched_history: push_history(state.sched_history, sched_avg_percent(metrics), size)
    }

    {:noreply, new_state}
  end

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(state) do
    [Subscription.interval(:refresh, state.refresh_ms, :refresh)]
  end

  # -- Header / Tabs / Footer --

  defp header_widget(state) do
    load = state.metrics.cpu_load
    cores = max(state.host.cpu_cores || 1, 1)

    text =
      Line.new(
        [
          Span.new(" "),
          Span.new("BEAM Monitor", style: %Style{fg: :cyan, modifiers: [:bold]}),
          Span.new("    "),
          Span.new("load avg", style: %Style{fg: :white, modifiers: [:bold]}),
          Span.new("  ")
        ] ++
          load_badge("1m", load.load1, cores) ++
          [Span.new("  ")] ++
          load_badge("5m", load.load5, cores) ++
          [Span.new("  ")] ++
          load_badge("15m", load.load15, cores)
      )

    %Paragraph{
      text: text,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("ExRatatui", style: %Style{fg: :magenta, modifiers: [:bold]}),
            Span.new(" + ", style: %Style{fg: :dark_gray}),
            Span.new("Nerves", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp load_badge(label, value, cores) do
    ratio = min(value / cores, 1.0)
    {bg, fg} = load_badge_colors(ratio)

    [
      Span.new(" #{label} ", style: %Style{fg: :dark_gray}),
      Span.new(" #{format_load(value)} ", style: %Style{bg: bg, fg: fg, modifiers: [:bold]})
    ]
  end

  defp load_badge_colors(ratio) do
    cond do
      ratio > 0.85 -> {:red, :white}
      ratio > 0.65 -> {:yellow, :black}
      true -> {:green, :black}
    end
  end

  defp tabs_widget(selected) do
    %Tabs{
      titles: [
        tab_title("1", "Overview"),
        tab_title("2", "Processes"),
        tab_title("3", "Graphs")
      ],
      selected: selected,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow}
      }
    }
  end

  # The keycap pins its own `fg: :white` so the Tabs' outer `style`
  # (`fg: :dark_gray`, applied to inactive tabs) can't bleed through and
  # paint the digit dark_gray-on-dark_gray. On the active tab the Tabs'
  # `highlight_style` patches fg to `:yellow`, which reads cleanly
  # against the same dark_gray pill background.
  defp tab_title(key, label) do
    Line.new([
      Span.new(" #{key} ", style: %Style{bg: :dark_gray, fg: :white, modifiers: [:bold]}),
      Span.new(" #{label}")
    ])
  end

  defp footer_widget do
    %Paragraph{
      text:
        Line.new([
          Span.new(" 1 ", style: %Style{bg: :cyan, fg: :black, modifiers: [:bold]}),
          Span.new("/"),
          Span.new(" 2 ", style: %Style{bg: :cyan, fg: :black, modifiers: [:bold]}),
          Span.new("/"),
          Span.new(" 3 ", style: %Style{bg: :cyan, fg: :black, modifiers: [:bold]}),
          Span.new(" tabs   "),
          Span.new(" j ", style: %Style{bg: :cyan, fg: :black, modifiers: [:bold]}),
          Span.new("/"),
          Span.new(" k ", style: %Style{bg: :cyan, fg: :black, modifiers: [:bold]}),
          Span.new(" scroll   "),
          Span.new(" q ", style: %Style{bg: :red, fg: :white, modifiers: [:bold]}),
          Span.new(" quit")
        ])
    }
  end

  # -- Overview Tab --

  defp render_overview(state, area) do
    [top_area, middle_area, bottom_area] =
      Layout.split(area, :vertical, [
        {:percentage, 38},
        {:percentage, 27},
        {:percentage, 35}
      ])

    [host_area, beam_area] =
      Layout.split(top_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [mem_gauges_area, mem_pools_area] =
      Layout.split(middle_area, :horizontal, [{:percentage, 45}, {:percentage, 55}])

    memory_children = render_memory_gauges(state, mem_gauges_area)

    [
      {host_info_widget(state), host_area},
      {beam_info_widget(state), beam_area},
      {memory_pools_widget(state), mem_pools_area},
      {scheduler_widget(state), bottom_area}
      | memory_children
    ]
  end

  defp host_info_widget(state) do
    host = state.host
    m = state.metrics

    {net_name, net_ip} =
      case host.primary_ip do
        {name, ip} -> {name, ip}
        nil -> {"--", "N/A"}
      end

    items = [
      info_line("OS", host.os, :white),
      info_line("Kernel", host.kernel, :white),
      info_line("CPU", "#{host.cpu_model} (#{host.cpu_cores})", :white),
      info_line("Uptime", format_uptime_seconds(m.host_uptime), :yellow),
      info_line("IP", "#{net_ip} (#{net_name})", :cyan)
    ]

    %WList{
      items: items,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("host: ", style: %Style{fg: :dark_gray}),
            Span.new(host.hostname, style: %Style{fg: :cyan, modifiers: [:bold]}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp beam_info_widget(state) do
    sys = state.metrics.sys

    items = [
      info_line("OTP", sys.otp_release, :white),
      info_line("ERTS", sys.erts_version, :white),
      info_line("Elixir", sys.elixir_version, :white),
      ratio_line("Schedulers", sys.schedulers_online, sys.schedulers),
      ratio_line("Processes", sys.process_count, sys.process_limit),
      ratio_line("Ports", sys.port_count, sys.port_limit),
      ratio_line("Atoms", sys.atom_count, sys.atom_limit),
      info_line("Uptime", format_uptime(sys.uptime_ms), :yellow)
    ]

    %WList{
      items: items,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("BEAM", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  # Two LineGauge widgets stacked: RAM used / total, and BEAM share of RAM.
  defp render_memory_gauges(state, area) do
    [ram_area, beam_area] =
      Layout.split(area, :vertical, [{:percentage, 50}, {:percentage, 50}])

    mem = state.metrics.mem
    used = mem.total - mem.available
    ram_ratio = safe_ratio(used, mem.total)
    {ram_fg, _} = ratio_colors(ram_ratio)

    ram_gauge = %LineGauge{
      ratio: ram_ratio,
      label: "#{format_bytes(used)} / #{format_bytes(mem.total)}   #{percentage_str(ram_ratio)}",
      filled_style: %Style{fg: ram_fg, modifiers: [:bold]},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("RAM", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    beam_total = mem.beam_total
    beam_ratio = safe_ratio(beam_total, mem.total)
    {beam_fg, _} = ratio_colors(beam_ratio)

    beam_gauge = %LineGauge{
      ratio: beam_ratio,
      label: "#{format_bytes(beam_total)}   #{percentage_str(beam_ratio)} of RAM",
      filled_style: %Style{fg: beam_fg, modifiers: [:bold]},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("BEAM heap", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    [{ram_gauge, ram_area}, {beam_gauge, beam_area}]
  end

  # BarChart expects non_neg_integer values. BEAM memory pools are bytes,
  # so we pass the raw byte counts as values and use `text_value` to show
  # a human-readable label instead of the huge number.
  defp memory_pools_widget(state) do
    mem = state.metrics.mem

    bars = [
      pool_bar("proc", mem.processes, :cyan),
      pool_bar("bin", mem.binary, :magenta),
      pool_bar("ets", mem.ets, :yellow),
      pool_bar("code", mem.code, :green)
    ]

    %BarChart{
      data: bars,
      bar_width: 6,
      bar_gap: 2,
      label_style: %Style{fg: :white},
      value_style: %Style{fg: :white, modifiers: [:bold]},
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("BEAM pools", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" — now ", style: %Style{fg: :dark_gray}),
            Span.new("proc ", style: %Style{fg: :dark_gray}),
            Span.new(format_bytes(mem.processes), style: %Style{fg: :cyan, modifiers: [:bold]}),
            Span.new(" · bin ", style: %Style{fg: :dark_gray}),
            Span.new(format_bytes(mem.binary), style: %Style{fg: :magenta, modifiers: [:bold]}),
            Span.new(" · ets ", style: %Style{fg: :dark_gray}),
            Span.new(format_bytes(mem.ets), style: %Style{fg: :yellow, modifiers: [:bold]}),
            Span.new(" · code ", style: %Style{fg: :dark_gray}),
            Span.new(format_bytes(mem.code), style: %Style{fg: :green, modifiers: [:bold]}),
            Span.new(" ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp pool_bar(label, bytes, color) do
    %Bar{
      label: label,
      value: bytes,
      text_value: format_bytes(bytes),
      style: %Style{fg: color}
    }
  end

  # Vertical BarChart — one bar per scheduler. Bar color reflects the
  # current utilization band, `text_value` renders a human percentage
  # instead of the raw 0..100 integer.
  defp scheduler_widget(state) do
    usages = state.metrics.sys.scheduler_usage

    bars =
      usages
      |> Enum.with_index(1)
      |> Enum.map(fn {usage, idx} ->
        pct = round(max(min(usage, 1.0), 0.0) * 100)
        {fg, _} = ratio_colors(usage)

        %Bar{
          label: "##{idx}",
          value: pct,
          text_value: "#{pct}%",
          style: %Style{fg: fg}
        }
      end)

    avg_pct = sched_avg_percent(state.metrics)
    peak_pct = sched_peak_percent(usages)
    {avg_fg, _} = ratio_colors(avg_pct / 100)
    {peak_fg, _} = ratio_colors(peak_pct / 100)

    %BarChart{
      data: bars,
      bar_width: 3,
      bar_gap: 1,
      max: 100,
      label_style: %Style{fg: :white},
      value_style: %Style{fg: :white, modifiers: [:bold]},
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Scheduler utilization", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" — now avg ", style: %Style{fg: :dark_gray}),
            Span.new("#{avg_pct}%", style: %Style{fg: avg_fg, modifiers: [:bold]}),
            Span.new(" · peak ", style: %Style{fg: :dark_gray}),
            Span.new("#{peak_pct}%", style: %Style{fg: peak_fg, modifiers: [:bold]}),
            Span.new(" ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp sched_peak_percent([]), do: 0

  defp sched_peak_percent(usages) do
    usages
    |> Enum.max()
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(100)
    |> round()
  end

  # -- Processes Tab --

  defp render_processes(state, area) do
    rows =
      Enum.map(state.metrics.top_procs, fn proc ->
        [
          Span.new(proc.name, style: %Style{fg: :white}),
          memory_cell(proc.memory),
          Span.new(Integer.to_string(proc.reductions), style: %Style{fg: :green}),
          msgq_cell(proc.message_queue_len)
        ]
      end)

    header = [
      Span.new("Process", style: %Style{fg: :cyan, modifiers: [:bold]}),
      Span.new("Memory", style: %Style{fg: :cyan, modifiers: [:bold]}),
      Span.new("Reductions", style: %Style{fg: :cyan, modifiers: [:bold]}),
      Span.new("MsgQ", style: %Style{fg: :cyan, modifiers: [:bold]})
    ]

    table = %Table{
      rows: rows,
      header: header,
      widths: [
        {:percentage, 45},
        {:percentage, 20},
        {:percentage, 22},
        {:percentage, 13}
      ],
      selected: state.selected,
      highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]},
      highlight_symbol: " > ",
      column_spacing: 1,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Top", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" #{state.top_n} "),
            Span.new("by memory", style: %Style{fg: :dark_gray}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    [{table, area}]
  end

  defp memory_cell(bytes) do
    fg =
      cond do
        bytes >= 50 * 1_048_576 -> :red
        bytes >= 5 * 1_048_576 -> :yellow
        true -> :green
      end

    Span.new(format_bytes(bytes), style: %Style{fg: fg, modifiers: [:bold]})
  end

  defp msgq_cell(0), do: Span.new("0", style: %Style{fg: :dark_gray})

  defp msgq_cell(n) when n < 100,
    do: Span.new(Integer.to_string(n), style: %Style{fg: :yellow, modifiers: [:bold]})

  defp msgq_cell(n),
    do: Span.new(Integer.to_string(n), style: %Style{fg: :red, modifiers: [:bold]})

  # -- Graphs Tab --

  defp render_graphs(state, area) do
    [ram_area, load_area, sched_area] =
      Layout.split(area, :vertical, [
        {:percentage, 40},
        {:percentage, 40},
        {:min, 0}
      ])

    [
      {ram_chart(state), ram_area},
      {load_chart(state), load_area},
      {sched_sparkline(state), sched_area}
    ]
  end

  defp ram_chart(state) do
    points = indexed_points(state.ram_history)

    %Chart{
      datasets: [
        %Dataset{
          name: "RAM %",
          data: points,
          graph_type: :line,
          marker: :braille,
          style: %Style{fg: :cyan}
        }
      ],
      x_axis: %Axis{
        bounds: {0.0, (state.history_size - 1) * 1.0},
        style: %Style{fg: :dark_gray},
        labels: [" -#{state.history_size}s ", " now "]
      },
      y_axis: %Axis{
        title: Span.new("%", style: %Style{fg: :dark_gray}),
        bounds: {0.0, 100.0},
        style: %Style{fg: :dark_gray},
        labels: ["0", "50", "100"]
      },
      legend_position: :top_right,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("RAM usage", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" — now ", style: %Style{fg: :dark_gray}),
            Span.new("#{ram_percent(state.metrics)}%",
              style: %Style{fg: :cyan, modifiers: [:bold]}
            ),
            Span.new(" — last #{state.history_size}s ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp load_chart(state) do
    history = Enum.reverse(state.load_history)

    load1 =
      history |> Enum.with_index() |> Enum.map(fn {{v, _, _}, i} -> {i * 1.0, v} end)

    load5 =
      history |> Enum.with_index() |> Enum.map(fn {{_, v, _}, i} -> {i * 1.0, v} end)

    load15 =
      history |> Enum.with_index() |> Enum.map(fn {{_, _, v}, i} -> {i * 1.0, v} end)

    cores = max(state.host.cpu_cores || 1, 1)
    y_max = max(cores * 1.5, highest_load(state.load_history) * 1.1)
    cur = state.metrics.cpu_load

    %Chart{
      datasets: [
        %Dataset{
          name: "1m",
          data: load1,
          graph_type: :line,
          marker: :braille,
          style: %Style{fg: :red}
        },
        %Dataset{
          name: "5m",
          data: load5,
          graph_type: :line,
          marker: :braille,
          style: %Style{fg: :yellow}
        },
        %Dataset{
          name: "15m",
          data: load15,
          graph_type: :line,
          marker: :braille,
          style: %Style{fg: :green}
        }
      ],
      x_axis: %Axis{
        bounds: {0.0, (state.history_size - 1) * 1.0},
        style: %Style{fg: :dark_gray},
        labels: [" -#{state.history_size}s ", " now "]
      },
      y_axis: %Axis{
        bounds: {0.0, y_max},
        style: %Style{fg: :dark_gray},
        labels: ["0", format_load(y_max / 2), format_load(y_max)]
      },
      legend_position: :top_right,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Load average", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" — #{cores} core#{if cores == 1, do: "", else: "s"} — now ",
              style: %Style{fg: :dark_gray}
            ),
            Span.new("1m ", style: %Style{fg: :dark_gray}),
            Span.new(format_load(cur.load1), style: %Style{fg: :red, modifiers: [:bold]}),
            Span.new(" · 5m ", style: %Style{fg: :dark_gray}),
            Span.new(format_load(cur.load5), style: %Style{fg: :yellow, modifiers: [:bold]}),
            Span.new(" · 15m ", style: %Style{fg: :dark_gray}),
            Span.new(format_load(cur.load15), style: %Style{fg: :green, modifiers: [:bold]}),
            Span.new(" ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp sched_sparkline(state) do
    %Sparkline{
      data: Enum.reverse(state.sched_history),
      max: 100,
      bar_set: :nine_levels,
      style: %Style{fg: :green},
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Avg scheduler utilization", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" — now ", style: %Style{fg: :dark_gray}),
            Span.new("#{sched_avg_percent(state.metrics)}%",
              style: %Style{fg: :green, modifiers: [:bold]}
            ),
            Span.new(" — last #{state.history_size}s ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  # -- Metrics collection (runs in Command.async) --

  # Belt-and-braces around `collect_metrics/2` for the async path: a
  # crashed collection shouldn't permanently strand `in_flight?` at
  # true and freeze the dashboard. Direct callers (tests, IEx) don't
  # need this — they want exceptions to propagate.
  defp safe_collect_metrics(prev_sched_sample, top_n) do
    try do
      collect_metrics(prev_sched_sample, top_n)
    rescue
      e ->
        Logger.error("collect_metrics crashed: #{Exception.message(e)}")
        :error
    end
  end

  @doc false
  def collect_metrics(prev_sched_sample, top_n \\ @default_top_n) do
    {scheduler_usage, new_sample} = collect_scheduler_usage(prev_sched_sample)
    beam = :erlang.memory()

    %{
      mem: build_memory_map(File.read("/proc/meminfo"), beam),
      sys: collect_system_info(scheduler_usage),
      host_uptime: read_host_uptime(),
      cpu_load: read_cpu_load(),
      top_procs: collect_top_processes(top_n),
      sched_sample: new_sample
    }
  end

  # -- Host info (collected once at init) --

  defp collect_host_info do
    %{
      hostname: read_hostname(),
      os: read_os_name(),
      kernel: read_kernel_version(),
      cpu_model: read_cpu_model(),
      cpu_cores: :erlang.system_info(:logical_processors),
      primary_ip: read_primary_ip()
    }
  end

  defp read_hostname do
    case File.read("/etc/hostname") do
      {:ok, name} -> String.trim(name)
      _ -> to_string(:net_adm.localhost())
    end
  end

  defp read_os_name do
    case File.read("/etc/os-release") do
      {:ok, content} ->
        case Regex.run(~r/PRETTY_NAME="([^"]+)"/, content) do
          [_, name] -> name
          _ -> "Linux"
        end

      _ ->
        {family, name} = :os.type()
        "#{family}/#{name}"
    end
  end

  defp read_kernel_version do
    case File.read("/proc/version") do
      {:ok, content} ->
        case Regex.run(~r/Linux version (\S+)/, content) do
          [_, version] -> version
          _ -> "Linux"
        end

      _ ->
        to_string(:erlang.system_info(:system_version)) |> String.trim()
    end
  end

  defp read_cpu_model do
    case File.read("/proc/cpuinfo") do
      {:ok, content} ->
        cond do
          match = Regex.run(~r/model name\s*:\s*(.+)/i, content) ->
            Enum.at(match, 1) |> String.trim() |> shorten_cpu_name()

          match = Regex.run(~r/Hardware\s*:\s*(.+)/i, content) ->
            Enum.at(match, 1) |> String.trim()

          true ->
            "Unknown"
        end

      _ ->
        "Unknown"
    end
  end

  defp shorten_cpu_name(name) do
    name
    |> String.replace(~r/\(R\)|\(TM\)/i, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp read_primary_ip do
    case :inet.getifaddrs() do
      {:ok, addrs} ->
        addrs
        |> Enum.flat_map(fn {name, opts} ->
          name_str = to_string(name)

          if name_str in ["lo", "lo0"] do
            []
          else
            opts
            |> Keyword.get_values(:addr)
            |> Enum.filter(fn addr -> tuple_size(addr) == 4 end)
            |> Enum.map(fn {a, b, c, d} -> {name_str, "#{a}.#{b}.#{c}.#{d}"} end)
          end
        end)
        |> List.first()

      _ ->
        nil
    end
  end

  # -- Dynamic data collection --

  @doc false
  def build_memory_map({:ok, content}, beam) do
    total_kb = parse_meminfo_kb(content, ~r/MemTotal:\s+(\d+)\s+kB/)
    available_kb = parse_meminfo_kb(content, ~r/MemAvailable:\s+(\d+)\s+kB/)

    %{
      total: total_kb * 1024,
      available: available_kb * 1024,
      beam_total: beam[:total],
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      code: beam[:code]
    }
  end

  def build_memory_map(_, beam) do
    total = beam[:total]

    %{
      total: total * 2,
      available: total,
      beam_total: total,
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      code: beam[:code]
    }
  end

  defp parse_meminfo_kb(content, regex) do
    case Regex.run(regex, content) do
      [_, kb_str] -> String.to_integer(kb_str)
      _ -> 0
    end
  end

  defp collect_system_info(scheduler_usage) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      otp_release: to_string(:erlang.system_info(:otp_release)),
      erts_version: to_string(:erlang.system_info(:version)),
      elixir_version: System.version(),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      uptime_ms: uptime_ms,
      scheduler_usage: scheduler_usage
    }
  end

  defp read_cpu_load do
    case File.read("/proc/loadavg") do
      {:ok, content} ->
        case String.split(content) do
          [l1, l5, l15 | _] ->
            %{load1: parse_float(l1), load5: parse_float(l5), load15: parse_float(l15)}

          _ ->
            %{load1: 0.0, load5: 0.0, load15: 0.0}
        end

      _ ->
        %{load1: 0.0, load5: 0.0, load15: 0.0}
    end
  end

  defp read_host_uptime do
    case File.read("/proc/uptime") do
      {:ok, content} ->
        case content |> String.split(" ") |> List.first() |> Float.parse() do
          {seconds, _} -> trunc(seconds)
          :error -> 0
        end

      _ ->
        {uptime_ms, _} = :erlang.statistics(:wall_clock)
        div(uptime_ms, 1000)
    end
  end

  defp collect_scheduler_usage(prev_sample) do
    online = :erlang.system_info(:schedulers_online)
    wall_times = :erlang.statistics(:scheduler_wall_time_all)

    current =
      wall_times
      |> Enum.filter(fn {id, _, _} -> id <= online end)
      |> Enum.sort_by(fn {id, _, _} -> id end)

    usage =
      case prev_sample do
        nil ->
          List.duplicate(0.0, online)

        prev ->
          Enum.zip(prev, current)
          |> Enum.map(fn {{_, prev_active, prev_total}, {_, cur_active, cur_total}} ->
            delta_total = cur_total - prev_total

            if delta_total > 0 do
              (cur_active - prev_active) / delta_total
            else
              0.0
            end
          end)
      end

    {usage, current}
  rescue
    _ -> {List.duplicate(0.0, :erlang.system_info(:schedulers_online)), nil}
  end

  defp collect_top_processes(n) do
    Process.list()
    |> Enum.map(&process_info/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(n)
  end

  defp process_info(pid) do
    case Process.info(pid, [:registered_name, :memory, :reductions, :message_queue_len]) do
      nil ->
        nil

      info ->
        name =
          case info[:registered_name] do
            [] -> inspect(pid)
            name -> inspect(name)
          end

        %{
          name: name,
          memory: info[:memory] || 0,
          reductions: info[:reductions] || 0,
          message_queue_len: info[:message_queue_len] || 0
        }
    end
  end

  # -- History helpers --

  # Internally newest-first: prepend O(1), truncate via pattern match.
  # Consumers that need chronological order (`indexed_points/1`) reverse
  # at read time — paid once per render, vs once per tick across three
  # histories.
  defp push_history(history, value, size) do
    [value | Enum.take(history, size - 1)]
  end

  defp indexed_points(list) do
    list
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {v, i} -> {i * 1.0, v * 1.0} end)
  end

  defp highest_load(history) do
    history
    |> Enum.map(fn {a, b, c} -> max(a, max(b, c)) end)
    |> Enum.max(fn -> 1.0 end)
  end

  defp ram_percent(metrics) do
    mem = metrics.mem
    used = mem.total - mem.available
    ratio = safe_ratio(used, mem.total)
    round(ratio * 100)
  end

  defp sched_avg_percent(metrics) do
    usage = metrics.sys.scheduler_usage

    case usage do
      [] ->
        0

      list ->
        avg = Enum.sum(list) / length(list)
        round(max(min(avg, 1.0), 0.0) * 100)
    end
  end

  # -- Info/ratio line helpers for the info lists --

  defp info_line(label, value, value_fg) do
    Line.new([
      Span.new(" "),
      Span.new(String.pad_trailing("#{label}:", 11), style: %Style{fg: :dark_gray}),
      Span.new(value, style: %Style{fg: value_fg})
    ])
  end

  defp ratio_line(label, used, total) do
    ratio = safe_ratio(used, total)
    {fg, _} = ratio_colors(ratio)

    Line.new([
      Span.new(" "),
      Span.new(String.pad_trailing("#{label}:", 11), style: %Style{fg: :dark_gray}),
      Span.new("#{used}", style: %Style{fg: fg, modifiers: [:bold]}),
      Span.new(" / #{total}", style: %Style{fg: :dark_gray}),
      Span.new("  (#{percentage_str(ratio)})", style: %Style{fg: fg})
    ])
  end

  # -- Formatting helpers --

  @doc false
  def safe_ratio(_num, 0), do: 0.0
  def safe_ratio(num, denom), do: (num / denom) |> max(0.0) |> min(1.0)

  defp ratio_colors(ratio) do
    cond do
      ratio > 0.85 -> {:red, :white}
      ratio > 0.65 -> {:yellow, :black}
      true -> {:green, :black}
    end
  end

  @doc false
  def format_bytes(bytes) when is_number(bytes) and bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  def format_bytes(bytes) when is_number(bytes) and bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def format_bytes(bytes) when is_number(bytes) and bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  def format_bytes(bytes) when is_number(bytes), do: "#{bytes} B"
  def format_bytes(_), do: "0 B"

  @doc false
  def format_uptime(ms), do: format_uptime_seconds(div(ms, 1000))

  @doc false
  def format_uptime_seconds(total_seconds) do
    days = div(total_seconds, 86_400)
    hours = div(rem(total_seconds, 86_400), 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
      true -> "#{minutes}m #{seconds}s"
    end
  end

  @doc false
  def format_load(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  @doc false
  def percentage_str(ratio) do
    pct = (ratio * 100) |> Float.round(0) |> trunc()
    "#{pct}%"
  end

  # -- Entry point --

  @doc """
  Starts the system monitor TUI (reducer runtime) and blocks until it exits.

  Accepts the same options as `start_link/1`.
  """
  def run(opts \\ []) do
    {:ok, pid} = start_link(opts)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
