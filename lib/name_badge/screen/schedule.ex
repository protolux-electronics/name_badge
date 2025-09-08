defmodule NameBadge.Screen.Schedule do
  alias NameBadge.ScheduleAPI
  use NameBadge.Screen

  require Logger

  def render(%{schedule: nil}) do
    """
    #place(center + horizon,
      stack(dir: ttb, text(size: 64pt, font: "New Amsterdam", "Error :("))
    );
    """
  end

  def render(%{next_sessions: [session_1, session_2], offset: offset}) do
    """
    #show heading: set text(font: "New Amsterdam", size: 32pt)
    #set text(size: 18pt,  font: "New Amsterdam")
    #set par(leading: 4pt)

    #grid(columns: (1fr, 1fr), column-gutter: 16pt)[
      = #{if offset == 0, do: "Right now", else: Calendar.strftime(session_1.starts_at, "%A")}
      #{session_1.title}
    ][
      = #{if offset == 0, do: "Up Next", else: Calendar.strftime(session_2.starts_at, "%A")}
      #{session_2.title}
    ]
    #grid(columns: (1fr, 1fr), column-gutter: 16pt)[
      #{Calendar.strftime(session_1.starts_at, "%-I:%M %P")} - #{Calendar.strftime(session_1.ends_at, "%-I:%M %P")}
    ][
      #{Calendar.strftime(session_2.starts_at, "%-I:%M %P")} - #{Calendar.strftime(session_2.ends_at, "%-I:%M %P")}
    ]

    #grid(columns: (1fr, 1fr), column-gutter: 16pt)[
      #{render_speakers(session_1.speakers)}
    ][
      #{render_speakers(session_2.speakers)}
    ]
    """
  end

  def render(%{next_sessions: [session], offset: offset}) do
    """
    #show heading: set text(font: "New Amsterdam", size: 32pt)
    #set text(size: 18pt,  font: "New Amsterdam")
    #set par(leading: 4pt)

    #grid(columns: (1fr, 1fr), column-gutter: 16pt)[
      = #{if offset == 0, do: "Right now", else: Calendar.strftime(session.starts_at, "%A")}
      #{session.title}
    ][]

    #grid(columns: (1fr, 1fr), column-gutter: 16pt)[
      #{Calendar.strftime(session.starts_at, "%-I:%M %P")} - #{Calendar.strftime(session.ends_at, "%-I:%M %P")}
    ][]

    #grid(columns: (1fr, 1fr), column-gutter: 16pt)[
      #{render_speakers(session.speakers)}
    ][]
    """
  end

  def render(%{next_sessions: []}) do
    """
    #set align(center + horizon)
    #set text(font: "New Amsterdam", size: 32pt)

    = Thanks for joining Goatmire 2025!
    """
  end

  def render_speakers(speakers) do
    speakers = Enum.map(speakers, &render_speaker/1) |> Enum.join()

    """
    #grid(columns: (32pt, 1fr), column-gutter: 4pt, row-gutter: 2pt)#{speakers}
    """
  end

  defp render_speaker(%{name: name, photo: photo}) do
    img_bytes =
      Base.decode64!(photo)
      |> :binary.bin_to_list()
      |> Enum.map(&to_string/1)
      |> Enum.join(", ")

    "[#image(bytes((#{img_bytes})))][#set align(left + horizon);#{name}]"
  end

  def init(_args, screen) do
    screen =
      case ScheduleAPI.load() do
        nil ->
          assign(screen, :schedule, nil)

        schedule ->
          next_sessions = ScheduleAPI.next_sessions(schedule) |> Enum.take(2)

          screen
          |> assign(:next_sessions, next_sessions)
          |> assign(:offset, 0)
      end

    {:ok, assign(screen, :button_hints, %{a: "Next", b: "Back"})}
  end

  def handle_button("BTN_1", 0, screen) do
    screen =
      case ScheduleAPI.load() do
        nil ->
          assign(screen, :schedule, nil)

        schedule ->
          new_offset = screen.assigns.offset + 2

          next_sessions =
            schedule
            |> ScheduleAPI.next_sessions()
            |> Enum.drop(new_offset)
            |> Enum.take(2)

          screen
          |> assign(:next_sessions, next_sessions)
          |> assign(:offset, new_offset)
      end

    {:render, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    {:render, navigate(screen, :back)}
  end

  def handle_button(_, _, screen) do
    {:norender, screen}
  end
end
