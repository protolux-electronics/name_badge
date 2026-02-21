defmodule NameBadge.Weather do
  @moduledoc """
  Weather service that fetches current weather data using location from
  NameBadge.TimezoneService and the OpenMeteo API.
  Provides fault-tolerant weather updates with caching.
  """

  use GenServer
  require Logger

  defstruct [
    :latitude,
    :longitude,
    :location_name,
    :weather_data,
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
  @openmeteo_url "https://api.open-meteo.com/v1/forecast"

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

    # Schedule initialization after a short delay to let TimezoneService start first
    :timer.send_after(1_000, :initialize)

    {:ok, initial_state}
  end

  @impl GenServer
  def handle_call(:get_current_weather, _from, state) do
    {:reply, state.weather_data, state}
  end

  @impl GenServer
  def handle_call(:get_location_name, _from, state) do
    {:reply, state.location_name, state}
  end

  @impl GenServer
  def handle_cast(:refresh_weather, state) do
    new_state = update_weather(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:initialize, state) do
    case get_location_from_timezone_service() do
      {:ok, lat, lon, location_name} ->
        Logger.info("Weather location: #{lat}, #{lon} (#{location_name})")

        new_state = %{
          state
          | latitude: lat,
            longitude: lon,
            location_name: location_name
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
        Logger.warning("No location available yet: #{inspect(reason)}")
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

  defp get_location_from_timezone_service do
    case NameBadge.TimezoneService.get_location() do
      {lat, lon, location_name} when not is_nil(lat) and not is_nil(lon) ->
        {:ok, lat, lon, location_name || "Unknown"}

      _ ->
        {:error, :no_location}
    end
  end

  defp update_weather(%{latitude: nil} = state), do: state
  defp update_weather(%{circuit_breaker_state: :open} = state), do: state

  defp update_weather(state) do
    case fetch_weather(state.latitude, state.longitude) do
      {:ok, weather} ->
        Logger.debug("Weather updated successfully")

        %{
          state
          | weather_data: weather,
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

  defp fetch_weather(latitude, longitude) do
    params = [
      latitude: latitude,
      longitude: longitude,
      current_weather: true,
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

        {:ok, weather}

      {:ok, %{status: status_code}} ->
        Logger.error("OpenMeteo API returned #{status_code}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("OpenMeteo API call failed: #{inspect(reason)}")
        {:error, :network_error}
    end
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
