defmodule NameBadge.Weather do
  @moduledoc """
  Weather service that fetches current weather data using IP-based location detection
  and the OpenMeteo API. Provides fault-tolerant weather updates with caching.
  """

  use GenServer
  require Logger

  defstruct [
    :latitude,
    :longitude,
    :location_source,
    :weather_data,
    :forecast_data,
    :last_updated,
    :timer,
    :failure_count,
    :circuit_breaker_state
  ]

  # Configuration
  # Respect API rate limits
  @update_interval :timer.minutes(10)
  @max_failures 3
  @circuit_breaker_timeout :timer.minutes(5)
  @call_timeout 5_000

  # API URLs
  @ip_geolocation_url "http://ip-api.com/json"
  @openmeteo_url "https://api.open-meteo.com/v1/forecast"
  @nominatim_url "https://nominatim.openstreetmap.org/reverse"

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc """
  Get current weather data. Returns nil if not available.
  """
  def get_current_weather do
    try do
      GenServer.call(__MODULE__, :get_current_weather, @call_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Weather service call timed out")
        nil

      :exit, {:noproc, _} ->
        Logger.warning("Weather service not available")
        nil
    end
  end

  @doc """
  Get 7-day daily forecast data. Returns nil if not available.
  Each entry is a map with keys: :date, :weather_code, :max_temp, :min_temp, :max_wind.
  """
  def get_forecast do
    try do
      GenServer.call(__MODULE__, :get_forecast, @call_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Weather service forecast call timed out")
        nil

      :exit, {:noproc, _} ->
        Logger.warning("Weather service not available for forecast")
        nil
    end
  end

  @doc """
  Force a weather update (useful for refresh button)
  """
  def refresh_weather do
    GenServer.cast(__MODULE__, :refresh_weather)
  end

  @doc """
  Get the current location name (e.g., "Berlin, Germany").
  Returns nil if not available.
  """
  def get_location_name do
    try do
      GenServer.call(__MODULE__, :get_location_name, @call_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Weather service location name call timed out")
        nil

      :exit, {:noproc, _} ->
        Logger.warning("Weather service not available for location name")
        nil
    end
  end

  # Server Callbacks

  @impl GenServer
  def init(state) do
    Logger.info("Initializing weather service...")

    # Start with circuit breaker closed
    initial_state = %{
      state
      | circuit_breaker_state: :closed,
        failure_count: 0
    }

    # Schedule initialization after a short delay
    :timer.send_after(1_000, :initialize)

    {:ok, initial_state}
  end

  @impl GenServer
  def handle_call(:get_current_weather, _from, state) do
    {:reply, state.weather_data, state}
  end

  @impl GenServer
  def handle_call(:get_forecast, _from, state) do
    {:reply, state.forecast_data, state}
  end

  @impl GenServer
  def handle_call(:get_location_name, _from, state) do
    {:reply, state.location_source, state}
  end

  @impl GenServer
  def handle_cast(:refresh_weather, state) do
    new_state = update_weather(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:initialize, state) do
    case get_location() do
      {:ok, lat, lon, source} ->
        Logger.info("Weather location: #{lat}, #{lon} (#{source})")

        new_state = %{
          state
          | latitude: lat,
            longitude: lon,
            location_source: source
        }

        # Schedule periodic updates
        case :timer.send_interval(@update_interval, :update_weather) do
          {:ok, timer} ->
            # Do initial weather fetch
            updated_state = update_weather(%{new_state | timer: timer})
            {:noreply, updated_state}

          {:error, reason} ->
            Logger.error("Failed to start weather update timer: #{inspect(reason)}")
            # Continue without timer - weather can still be refreshed manually
            updated_state = update_weather(new_state)
            {:noreply, updated_state}
        end

      {:error, reason} ->
        Logger.error("Failed to get location: #{inspect(reason)}")
        # Retry initialization in 30 seconds
        :timer.send_after(30_000, :initialize)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:update_weather, state) do
    new_state = update_weather(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:retry_after_circuit_breaker, state) do
    Logger.debug("Retrying weather service after circuit breaker timeout")
    new_state = %{state | circuit_breaker_state: :half_open}
    updated_state = update_weather(new_state)
    {:noreply, updated_state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.timer, do: :timer.cancel(state.timer)
    :ok
  end

  # Private Functions

  defp update_weather(%{latitude: nil} = state), do: state
  defp update_weather(%{circuit_breaker_state: :open} = state), do: state

  defp update_weather(state) do
    case fetch_weather(state.latitude, state.longitude) do
      {:ok, weather, forecast} ->

        %{
          state
          | weather_data: weather,
            forecast_data: forecast,
            last_updated: DateTime.utc_now(),
            failure_count: 0,
            circuit_breaker_state: :closed
        }

      {:error, reason} ->
        Logger.warning("Weather update failed: #{inspect(reason)}")
        record_failure(state, reason)
    end
  rescue
    error ->
      Logger.error("Unexpected error updating weather: #{inspect(error)}")
      record_failure(state, error)
  end

  defp get_location do
    case get_configured_location() do
      {:ok, lat, lon, source} ->
        {:ok, lat, lon, source}

      :not_configured ->
        get_location_from_ip()
    end
  end

  defp get_configured_location do
    # Environment variables take precedence over config
    env_lat = System.get_env("WEATHER_LATITUDE")
    env_lon = System.get_env("WEATHER_LONGITUDE")
    env_name = System.get_env("WEATHER_LOCATION_NAME")

    weather_config = Application.get_env(:name_badge, :weather, [])

    config_lat = Keyword.get(weather_config, :latitude)
    config_lon = Keyword.get(weather_config, :longitude)
    config_name = Keyword.get(weather_config, :name)

    lat = parse_coordinate(env_lat) || config_lat
    lon = parse_coordinate(env_lon) || config_lon
    explicit_name = env_name || config_name

    if lat && lon do
      location_name = explicit_name || reverse_geocode(lat, lon) || "Configured Location"
      Logger.info("Using configured location: #{lat}, #{lon} (#{location_name})")
      {:ok, lat, lon, location_name}
    else
      :not_configured
    end
  end

  defp parse_coordinate(nil), do: nil

  defp parse_coordinate(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp reverse_geocode(lat, lon) do
    Logger.debug("Reverse geocoding coordinates: #{lat}, #{lon}")

    params = [
      lat: lat,
      lon: lon,
      format: "json",
      zoom: 10
    ]

    headers = [{"user-agent", "NameBadge/1.0"}]

    case Req.get(@nominatim_url, params: params, headers: headers, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"address" => address}}} ->
        city = address["city"] || address["town"] || address["village"] || address["municipality"]
        country = address["country"]

        case {city, country} do
          {nil, nil} -> nil
          {nil, country} -> country
          {city, nil} -> city
          {city, country} -> "#{city}, #{country}"
        end

      {:ok, response} ->
        Logger.warning("Unexpected response from Nominatim: #{inspect(response)}")
        nil

      {:error, reason} ->
        Logger.warning("Reverse geocoding failed: #{inspect(reason)}")
        nil
    end
  end

  defp get_location_from_ip do
    Logger.info("Detecting location via IP geolocation...")

    request_options = [
      retry: :transient,
      max_retries: 2,
      retry_delay: fn attempt -> trunc(:math.pow(2, attempt - 1) * 500) end,
      connect_options: [timeout: 8_000]
    ]

    case Req.get(@ip_geolocation_url, request_options) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"lat" => lat, "lon" => lon, "city" => city, "country" => country}
       }} ->
        location_name = "#{city}, #{country}"
        {:ok, lat, lon, location_name}

      {:ok, response} ->
        Logger.error("Unexpected response from IP geolocation: #{inspect(response)}")
        {:error, "Invalid response from IP geolocation service"}

      {:error, exception} ->
        Logger.error("Failed to get location from IP: #{inspect(exception)}")
        {:error, "Failed to get location from IP"}
    end
  end

  defp fetch_weather(latitude, longitude) do
    params = [
      latitude: latitude,
      longitude: longitude,
      current_weather: true,
      daily: "weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max",
      forecast_days: 7,
      timezone: "auto"
    ]

    case Req.get(@openmeteo_url, params: params, receive_timeout: 8_000) do
      {:ok, %{status: 200, body: data}} ->
        current = data["current_weather"]
        units = data["current_weather_units"] || %{}

        weather = %{
          temperature: current["temperature"],
          wind_speed: current["windspeed"],
          weather_code: current["weathercode"],
          is_day: current["is_day"] == 1,
          timestamp: current["time"],
          temperature_unit: units["temperature"] || "°C",
          wind_speed_unit: units["windspeed"] || "km/h"
        }

        forecast = parse_daily_forecast(data)

        {:ok, weather, forecast}

      {:ok, %{status: status_code}} ->
        Logger.error("OpenMeteo API returned #{status_code}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("OpenMeteo API call failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_daily_forecast(%{"daily" => daily, "daily_units" => daily_units}) do
    dates = daily["time"] || []
    weather_codes = daily["weather_code"] || []
    max_temps = daily["temperature_2m_max"] || []
    min_temps = daily["temperature_2m_min"] || []
    max_winds = daily["wind_speed_10m_max"] || []

    temp_unit = daily_units["temperature_2m_max"] || "°C"
    wind_unit = daily_units["wind_speed_10m_max"] || "km/h"

    dates
    |> Enum.with_index()
    |> Enum.map(fn {date, i} ->
      %{
        date: date,
        weather_code: Enum.at(weather_codes, i),
        max_temp: Enum.at(max_temps, i),
        min_temp: Enum.at(min_temps, i),
        max_wind: Enum.at(max_winds, i),
        temperature_unit: temp_unit,
        wind_speed_unit: wind_unit
      }
    end)
  end

  defp parse_daily_forecast(_data) do
    Logger.warning("No daily forecast data in API response")
    []
  end

  defp record_failure(state, _reason) do
    new_failure_count = state.failure_count + 1

    new_state = %{
      state
      | failure_count: new_failure_count
    }

    if new_failure_count >= @max_failures do
      Logger.warning("Circuit breaker opened after #{new_failure_count} failures")
      :timer.send_after(@circuit_breaker_timeout, :retry_after_circuit_breaker)
      %{new_state | circuit_breaker_state: :open}
    else
      new_state
    end
  end
end
