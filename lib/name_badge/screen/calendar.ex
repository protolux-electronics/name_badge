defmodule NameBadge.Screen.Calendar do
  @moduledoc """
  Calendar screen with three views: Day, Week, and Month.

  - Long press A: Cycle views (Day -> Week -> Month).
  - A (single press): Navigate to the next day / week / month.
  - B (single press): Navigate to the previous day / week / month.
  - Long press B: Navigate back to main menu (handled by Screen behaviour).
  """

  use NameBadge.Screen

  require Logger

  @views [:day, :week, :month]
  @timezone "Etc/UTC"

  # ── Callbacks ───────────────────────────────────────────────────────────

  @impl NameBadge.Screen
  def mount(args, screen) do
    events = NameBadge.CalendarService.get_events()
    now = DateTime.now!(@timezone)
    today = DateTime.to_date(now)

    # Allow overriding the selected_date via mount_args for testing
    selected_date =
      case args do
        %{selected_date: date} when is_struct(date, Date) -> date
        [selected_date: date] when is_struct(date, Date) -> date
        _ -> today
      end

    screen =
      screen
      |> assign(
        view: :day,
        events: events,
        now: now,
        today: today,
        selected_date: selected_date
      )
      |> assign(button_hints: %{a: "Next", b: "Prev"})

    # Refresh the cached events and current time every minute
    Process.send_after(self(), :tick, :timer.minutes(1))

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, :long_press, screen) do
    # Cycle view: Day -> Week -> Month -> Day
    current_index = Enum.find_index(@views, &(&1 == screen.assigns.view))
    next_view = Enum.at(@views, rem(current_index + 1, length(@views)))

    {:noreply, assign(screen, view: next_view)}
  end

  def handle_button(:button_1, :single_press, screen) do
    # Navigate forward by one period
    {:noreply,
     assign(screen, selected_date: advance(screen.assigns.selected_date, screen.assigns.view, 1))}
  end

  def handle_button(:button_2, :single_press, screen) do
    # Navigate backward by one period
    {:noreply,
     assign(screen, selected_date: advance(screen.assigns.selected_date, screen.assigns.view, -1))}
  end

  def handle_button(_, _, screen), do: {:noreply, screen}

  @impl NameBadge.Screen
  def handle_info(:tick, screen) do
    now = DateTime.now!(@timezone)
    events = NameBadge.CalendarService.get_events()
    Process.send_after(self(), :tick, :timer.minutes(1))

    {:noreply, assign(screen, now: now, today: DateTime.to_date(now), events: events)}
  end

  # ── Navigation helpers ─────────────────────────────────────────────────

  defp advance(date, :day, direction), do: Date.add(date, direction)
  defp advance(date, :week, direction), do: Date.add(date, 7 * direction)

  defp advance(date, :month, direction) do
    month = date.month + direction
    year = date.year

    {year, month} =
      cond do
        month > 12 -> {year + 1, month - 12}
        month < 1 -> {year - 1, month + 12}
        true -> {year, month}
      end

    day = min(date.day, Date.days_in_month(Date.new!(year, month, 1)))
    Date.new!(year, month, day)
  end

  # ── Render dispatch ─────────────────────────────────────────────────────

  @impl NameBadge.Screen
  def render(%{view: :day} = assigns), do: render_day(assigns)
  def render(%{view: :week} = assigns), do: render_week(assigns)
  def render(%{view: :month} = assigns), do: render_month(assigns)

  # ── Day View ────────────────────────────────────────────────────────────

  defp render_day(%{events: events, selected_date: selected_date, now: now, today: today}) do
    day_label = Calendar.strftime(selected_date, "%A, %B %d")
    is_today = Date.compare(selected_date, today) == :eq
    day_events = events_on_date(events, selected_date)

    today_marker = if is_today, do: " (Today)", else: ""

    event_rows =
      if Enum.empty?(day_events) do
        """
        #text(size: 16pt, style: "italic")[No events]
        """
      else
        table_rows =
          day_events
          |> Enum.take(6)
          |> Enum.flat_map(fn evt ->
            start_time = format_time(evt.dtstart)
            end_time = if evt.dtend, do: format_time(evt.dtend), else: ""
            summary = escape_typst(evt.summary)
            is_now = is_today and event_is_now?(evt, now)
            weight = if is_now, do: "700", else: "400"

            [
              "text(size: 16pt, weight: #{weight})[#{start_time}]",
              "text(size: 16pt, weight: #{weight})[#{end_time}]",
              "text(size: 16pt, weight: #{weight})[#{truncate(summary, 30)}]"
            ]
          end)
          |> Enum.join(", ")

        """
        #set text(size: 16pt)

        #table(columns: (auto, auto, 1fr), align: left, inset: 6pt, stroke: none, "Start", "End", "Description", #{table_rows})
        """
      end

    """
    #show heading: set text(font: "Silkscreen", size: 28pt, weight: 400, tracking: -4pt)

    = Calendar

    #v(4pt)

    #align(center)[
      #text(size: 18pt, weight: 600)[#{day_label}#{today_marker}]

      #{event_rows}
    ]
    """
  end

  # ── Week View ───────────────────────────────────────────────────────────

  defp render_week(%{events: events, selected_date: selected_date, today: today}) do
    # Find the Monday of the week containing selected_date
    dow = Date.day_of_week(selected_date)
    week_start = Date.add(selected_date, -(dow - 1))

    week_label =
      "#{Calendar.strftime(week_start, "%b %d")} - #{Calendar.strftime(Date.add(week_start, 6), "%b %d")}"

    days = Enum.map(0..6, fn offset -> Date.add(week_start, offset) end)

    day_rows =
      days
      |> Enum.flat_map(fn date ->
        day_events = events_on_date(events, date)
        day_name = Calendar.strftime(date, "%a %d")
        count = length(day_events)

        first_event =
          case day_events do
            [evt | _] -> truncate(escape_typst(evt.summary), 36)
            [] -> "---"
          end

        suffix = if count > 1, do: " (+#{count - 1})", else: ""
        is_today = Date.compare(date, today) == :eq
        weight = if is_today, do: "700", else: "400"

        [
          "[#text(size: 14pt, weight: #{weight})[#{day_name}]]",
          "[#text(size: 14pt, weight: #{weight})[#{first_event} #{suffix}]]"
        ]
      end)
      |> Enum.join(", ")

    """
    #show heading: set text(font: "Silkscreen", size: 28pt, weight: 400, tracking: -4pt)

    = Calendar

    #v(4pt)

    #align(center)[
      #text(size: 18pt, weight: 600)[#{week_label}]
    ]

    #v(-8pt)

    #table(columns: (auto, 1fr), inset: 6pt, stroke: none, #{day_rows})
    """
  end

  # ── Month View ──────────────────────────────────────────────────────────

  defp render_month(%{events: events, selected_date: selected_date, today: today}) do
    year = selected_date.year
    month = selected_date.month

    month_label =
      Calendar.strftime(Date.new!(year, month, 1), "%B %Y")

    # First day of the month
    first = Date.new!(year, month, 1)
    # Day of week for the first: 1=Mon .. 7=Sun
    first_dow = Date.day_of_week(first)

    # Calculate 49 cells (7 columns x 7 rows)
    # Start from Monday of the week containing the 1st
    grid_start = Date.add(first, -(first_dow - 1))

    cells =
      0..48
      |> Enum.map(fn offset ->
        date = Date.add(grid_start, offset)
        day_num = date.day
        is_current_month = date.month == month
        is_today = Date.compare(date, today) == :eq
        has_events = Enum.any?(events, &event_on_date?(&1, date))

        {day_num, is_current_month, is_today, has_events}
      end)

    cell_markup =
      cells
      |> Enum.map_join(",\n", fn {day_num, is_current_month, is_today, has_events} ->
        fill = if is_today, do: "black", else: "white"

        text_fill =
          if is_today, do: "white", else: if(is_current_month, do: "black", else: "gray")

        day_str = Integer.to_string(day_num)

        dot =
          cond do
            not is_current_month -> ""
            has_events and not is_today -> "#circle(radius: 2pt, fill: black)"
            has_events and is_today -> "#circle(radius: 2pt, fill: white)"
            true -> ""
          end

        """
        box(width: 40pt, height: 30pt, fill: #{fill}, stroke: 0.5pt + gray, inset: 1pt)[
          #set align(center + top)
          #text(size: 12pt, fill: #{text_fill})[#{day_str}]
          #v(-18pt)
          #{dot}
        ]
        """
      end)

    header_cells =
      ~w(Mo Tu We Th Fr Sa Su)
      |> Enum.map_join(",\n", fn label ->
        """
        box(width: 40pt, height: 16pt)[
          #set align(center + top)
          #text(size: 12pt, weight: 700)[#{label}]
        ]
        """
      end)

    """
    #show heading: set text(font: "Silkscreen", size: 28pt, weight: 400, tracking: -4pt)

    = Calendar

    #v(4pt)

    #align(center)[
      #text(size: 18pt, weight: 600)[#{month_label}]
      #v(-8pt)
      #grid(
        columns: (1fr,) * 7,
        gutter: 0pt,
        #{header_cells},
        #{cell_markup}
      )
    ]
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp events_on_date(events, date) do
    Enum.filter(events, &event_on_date?(&1, date))
    |> Enum.sort_by(& &1.dtstart, DateTime)
  end

  defp event_on_date?(%{dtstart: nil}, _date), do: false

  defp event_on_date?(%{dtstart: dtstart, dtend: dtend}, date) do
    event_date = DateTime.to_date(dtstart)

    end_date =
      if dtend do
        DateTime.to_date(dtend)
      else
        event_date
      end

    Date.compare(date, event_date) in [:eq, :gt] and
      Date.compare(date, end_date) in [:eq, :lt]
  end

  defp event_is_now?(%{dtstart: dtstart, dtend: dtend}, now) do
    after_start = DateTime.compare(now, dtstart) in [:eq, :gt]

    before_end =
      if dtend do
        DateTime.compare(now, dtend) in [:eq, :lt]
      else
        false
      end

    after_start and before_end
  end

  defp format_time(nil), do: "--:--"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp truncate(str, max_len) when byte_size(str) <= max_len, do: str

  defp truncate(str, max_len) do
    String.slice(str, 0, max_len - 2) <> "..."
  end

  defp escape_typst(nil), do: ""

  defp escape_typst(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("#", "\\#")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("\"", "\\\"")
  end
end
