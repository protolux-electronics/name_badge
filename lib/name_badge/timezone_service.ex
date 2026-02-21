defmodule NameBadge.TimezoneService do
  @moduledoc """
  Service that manages timezone and location detection.

  On boot:
    1. Loads timezone/lat/lon from NameBadge.Config (persisted JSON).
    2. Falls back to "Europe/Stockholm" if nothing is stored.
    3. Subscribes to VintageNet network events for wlan0.
    4. When the network becomes available, fetches location and timezone
       from ip-api.com, with up to 3 retries (5 s sleep between attempts).
    5. On success, persists to config.json and updates Application env.
  """

  use GenServer
  require Logger

  @default_timezone "Europe/Stockholm"
  @ip_geolocation_url "http://ip-api.com/json"
  @nominatim_url "https://nominatim.openstreetmap.org/reverse"

  @wlan0_connection ["interface", "wlan0", "connection"]

  @max_attempts 3
  @retry_delay :timer.seconds(5)

  defstruct [
    :timezone,
    :latitude,
    :longitude,
    :location_name,
    :attempt
  ]

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns the current timezone string (e.g. "Europe/Stockholm").
  """
  def get_timezone do
    GenServer.call(__MODULE__, :get_timezone)
  end

  @doc """
  Returns `{latitude, longitude, location_name}` or `{nil, nil, nil}`.
  """
  def get_location do
    GenServer.call(__MODULE__, :get_location)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    config = NameBadge.Config.load_config()

    timezone = Map.get(config, "timezone", @default_timezone)
    latitude = Map.get(config, "latitude")
    longitude = Map.get(config, "longitude")
    location_name = Map.get(config, "location_name")

    # Set the application env so NameBadge.timezone/0 returns the persisted value
    Application.put_env(:name_badge, :timezone, timezone)

    state = %__MODULE__{
      timezone: timezone,
      latitude: latitude,
      longitude: longitude,
      location_name: location_name,
      attempt: 0
    }

    # Subscribe to network status changes (no-op on host)
    NameBadge.Network.subscribe(@wlan0_connection)

    # If we are already connected, kick off the first fetch
    if NameBadge.Network.connected?(@wlan0_connection) do
      send(self(), :fetch_from_network)
    end

    Logger.info(
      "TimezoneService started – timezone=#{timezone}, lat=#{inspect(latitude)}, lon=#{inspect(longitude)}"
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_timezone, _from, state) do
    {:reply, state.timezone, state}
  end

  @impl GenServer
  def handle_call(:get_location, _from, state) do
    {:reply, {state.latitude, state.longitude, state.location_name}, state}
  end

  # VintageNet property change – network came up
  @impl GenServer
  def handle_info(
        {VintageNet, @wlan0_connection, _old, :internet, _meta},
        state
      ) do
    Logger.info("TimezoneService: network is up, scheduling fetch")
    send(self(), :fetch_from_network)
    {:noreply, %{state | attempt: 0}}
  end

  # Ignore other VintageNet property changes
  def handle_info({VintageNet, @wlan0_connection, _old, _new, _meta}, state) do
    {:noreply, state}
  end

  # Attempt a network fetch with retry logic
  @impl GenServer
  def handle_info(:fetch_from_network, %{attempt: attempt} = state)
      when attempt >= @max_attempts do
    Logger.warning(
      "TimezoneService: all #{@max_attempts} fetch attempts exhausted, keeping current values"
    )

    {:noreply, state}
  end

  def handle_info(:fetch_from_network, state) do
    attempt = state.attempt + 1
    Logger.info("TimezoneService: fetch attempt #{attempt}/#{@max_attempts}")

    case fetch_location_and_timezone() do
      {:ok, data} ->
        new_state = apply_fetched_data(state, data)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("TimezoneService: fetch failed (#{inspect(reason)}), attempt #{attempt}")
        :timer.send_after(@retry_delay, :fetch_from_network)
        {:noreply, %{state | attempt: attempt}}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp fetch_location_and_timezone do
    request_opts = [
      connect_options: [timeout: 8_000],
      receive_timeout: 8_000
    ]

    case Req.get(@ip_geolocation_url, request_opts) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"lat" => lat, "lon" => lon, "timezone" => tz} = body
       }} ->
        city = body["city"]
        country = body["country"]

        location_name =
          reverse_geocode(lat, lon) || build_location_name(city, country)

        {:ok,
         %{
           timezone: tz,
           latitude: lat,
           longitude: lon,
           location_name: location_name
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reverse_geocode(lat, lon) do
    params = [lat: lat, lon: lon, format: "json", zoom: 10]
    headers = [{"user-agent", "NameBadge/1.0"}]

    case Req.get(@nominatim_url,
           params: params,
           headers: headers,
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"address" => address}}} ->
        city =
          address["city"] || address["town"] || address["village"] ||
            address["municipality"]

        country = address["country"]
        build_location_name(city, country)

      _ ->
        nil
    end
  end

  defp build_location_name(nil, nil), do: nil
  defp build_location_name(nil, country), do: country
  defp build_location_name(city, nil), do: city
  defp build_location_name(city, country), do: "#{city}, #{country}"

  defp apply_fetched_data(state, data) do
    timezone = data.timezone
    latitude = data.latitude
    longitude = data.longitude
    location_name = data.location_name

    # Update application env
    Application.put_env(:name_badge, :timezone, timezone)

    # Persist to config.json
    current_config = NameBadge.Config.load_config()

    updated_config =
      Map.merge(current_config, %{
        "timezone" => timezone,
        "latitude" => latitude,
        "longitude" => longitude,
        "location_name" => location_name
      })

    NameBadge.Config.store_config(updated_config)

    Logger.info(
      "TimezoneService: updated – timezone=#{timezone}, lat=#{latitude}, lon=#{longitude}, location=#{location_name}"
    )

    # Notify other services via the Registry
    Registry.dispatch(NameBadge.Registry, :timezone_updated, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:timezone_updated, timezone, latitude, longitude, location_name})
      end
    end)

    %{
      state
      | timezone: timezone,
        latitude: latitude,
        longitude: longitude,
        location_name: location_name,
        attempt: 0
    }
  end
end
