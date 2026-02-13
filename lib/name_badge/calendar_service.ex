defmodule NameBadge.CalendarService do
  @moduledoc """
  Background service that periodically fetches and parses iCal data from a
  configured URL. Provides an API to retrieve parsed calendar events.

  The service is entirely disabled when no CALENDAR_URL is configured.
  """

  use GenServer

  require Logger

  defstruct [:url, :refresh_interval, :timer, events: [], last_fetched: nil]

  # ── Client API ──────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if the calendar feature is configured and enabled.
  """
  def enabled? do
    config = Application.get_env(:name_badge, :calendar)
    config != nil and Keyword.get(config, :url) != nil
  end

  @doc """
  Returns the list of parsed calendar events sorted by start time.
  Each event is a map with keys: :summary, :dtstart, :dtend, :description, :location.
  """
  def get_events do
    if enabled?() do
      GenServer.call(__MODULE__, :get_events, 5_000)
    else
      []
    end
  end

  @doc """
  Force an immediate refresh from the iCal URL.
  """
  def refresh do
    if enabled?() do
      GenServer.cast(__MODULE__, :refresh)
    end
  end

  # ── Server Callbacks ────────────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    config = Application.get_env(:name_badge, :calendar)

    url = Keyword.fetch!(config, :url)
    refresh_interval = Keyword.get(config, :refresh_interval, 300_000)

    state = %__MODULE__{
      url: url,
      refresh_interval: refresh_interval
    }

    # Do the first fetch after a short delay to let the network come up
    Process.send_after(self(), :fetch, 5_000)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_events, _from, state) do
    {:reply, state.events, state}
  end

  @impl GenServer
  def handle_cast(:refresh, state) do
    state = do_fetch(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:fetch, state) do
    state = do_fetch(state)
    schedule_next_fetch(state.refresh_interval)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    :ok
  end

  # ── Private ─────────────────────────────────────────────────────────────

  defp do_fetch(state) do
    Logger.info("CalendarService: fetching iCal data from #{state.url}")

    case Req.get(state.url, receive_timeout: 15_000, connect_options: [timeout: 10_000]) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        events = parse_ics(body)
        Logger.info("CalendarService: parsed #{length(events)} events")

        %{state | events: events, last_fetched: DateTime.utc_now()}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("CalendarService: unexpected HTTP status #{status}")
        state

      {:error, reason} ->
        Logger.warning("CalendarService: fetch failed: #{inspect(reason)}")
        state
    end
  end

  defp parse_ics(ics_text) do
    ics_text
    |> ICalendar.from_ics()
    |> List.wrap()
    |> Enum.filter(&is_struct(&1, ICalendar.Event))
    |> Enum.map(&normalize_event/1)
    |> Enum.filter(&(&1.dtstart != nil))
    |> Enum.sort_by(& &1.dtstart, DateTime)
  end

  defp normalize_event(%ICalendar.Event{} = event) do
    %{
      summary: event.summary || "(No title)",
      dtstart: to_datetime(event.dtstart),
      dtend: to_datetime(event.dtend),
      description: event.description,
      location: event.location
    }
  end

  defp to_datetime(%DateTime{} = dt), do: dt

  defp to_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_datetime(%Date{} = date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp to_datetime(nil), do: nil

  defp to_datetime(other) do
    Logger.warning("CalendarService: unexpected date format: #{inspect(other)}")
    nil
  end

  defp schedule_next_fetch(interval) do
    Process.send_after(self(), :fetch, interval)
  end
end
