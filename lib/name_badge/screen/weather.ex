defmodule NameBadge.Screen.Weather do
  @moduledoc """
  Weather screen that displays current weather information.
  """

  use NameBadge.Screen

  require Logger

  @impl NameBadge.Screen
  def render(%{weather: nil, loading: true}) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Weather

    #v(16pt)

    #place(center + horizon, text(size: 24pt)[Loading weather data...])
    """
  end

  def render(%{weather: nil, error: error}) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Weather

    #v(16pt)

    #place(center + horizon,
      stack(dir: ttb, spacing: 8pt,
        text(size: 20pt, fill: red)[Error],
        text(size: 16pt)[#{error}]
      )
    )
    """
  end

  def render(%{weather: weather, location: location}) do
    temp_display = format_temperature(weather.temperature)
    condition = weather_condition_text(weather.weather_code, weather.is_day)
    wind_display = format_wind_speed(weather.wind_speed)

    """
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Weather

    #v(8pt)

    #place(center + horizon,
      stack(dir: ttb, spacing: 12pt,

        // Location
        text(size: 16pt, style: "italic")[#{location || "Unknown Location"}],

        // Temperature (main display)
        text(size: 48pt, font: "New Amsterdam")[#{temp_display}],

        // Weather condition
        text(size: 18pt)[#{condition}],

        // Wind speed
        text(size: 14pt)[Wind: #{wind_display}],

        // Last updated
        text(size: 12pt, fill: gray)[#{format_last_updated(weather.timestamp)}]
      )
    )
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    # Get initial weather data
    weather = NameBadge.Weather.get_current_weather()

    screen =
      case weather do
        nil ->
          screen
          |> assign(weather: nil, loading: true, location: nil)
          |> assign(button_hints: %{a: "Refresh", b: "Back"})

        weather_data ->
          screen
          |> assign(weather: weather_data, loading: false, location: get_location_name())
          |> assign(button_hints: %{a: "Refresh", b: "Back"})
      end

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, screen) do
    # Refresh weather data
    Logger.info("Refreshing weather data...")
    NameBadge.Weather.refresh_weather()

    # Show loading state
    screen =
      screen
      |> assign(loading: true, error: nil)

    # Schedule a check for updated data in 2 seconds
    Process.send_after(self(), :check_weather_update, 2_000)

    {:noreply, screen}
  end

  def handle_button(:button_2, :single_press, screen) do
    # Button B does nothing - navigation back is handled by long press on button 2
    {:noreply, screen}
  end

  def handle_button(_, _, screen), do: {:noreply, screen}

  @impl NameBadge.Screen
  def handle_info(:check_weather_update, screen) do
    weather = NameBadge.Weather.get_current_weather()

    screen =
      case weather do
        nil ->
          assign(screen, weather: nil, loading: false, error: "Unable to fetch weather data")

        weather_data ->
          assign(screen, weather: weather_data, loading: false, error: nil, location: get_location_name())
      end

    {:noreply, screen}
  end

  # Private helper functions

  defp format_temperature(temp) when is_number(temp) do
    "#{round(temp)}°C"
  end
  defp format_temperature(_), do: "N/A"

  defp format_wind_speed(speed) when is_number(speed) do
    "#{round(speed)} m/s"
  end
  defp format_wind_speed(_), do: "N/A"

  defp format_last_updated(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp <> ":00Z") do
      {:ok, dt, _} ->
        now = DateTime.utc_now()
        diff_minutes = div(DateTime.diff(now, dt), 60)

        cond do
          diff_minutes < 1 -> "Just now"
          diff_minutes < 60 -> "#{diff_minutes}m ago"
          true -> "#{div(diff_minutes, 60)}h ago"
        end

      _ -> "Recently"
    end
  end
  defp format_last_updated(_), do: "Recently"

  defp weather_condition_text(code, is_day) when is_number(code) do
    case code do
      0 -> "Clear sky"
      1 -> "Mainly clear"
      2 -> "Partly cloudy"
      3 -> "Overcast"
      45 -> "Fog"
      48 -> "Depositing rime fog"
      51 -> "Light drizzle"
      53 -> "Moderate drizzle"
      55 -> "Dense drizzle"
      56 -> "Light freezing drizzle"
      57 -> "Dense freezing drizzle"
      61 -> "Slight rain"
      63 -> "Moderate rain"
      65 -> "Heavy rain"
      66 -> "Light freezing rain"
      67 -> "Heavy freezing rain"
      71 -> "Slight snow fall"
      73 -> "Moderate snow fall"
      75 -> "Heavy snow fall"
      77 -> "Snow grains"
      80 -> "Slight rain showers"
      81 -> "Moderate rain showers"
      82 -> "Violent rain showers"
      85 -> "Slight snow showers"
      86 -> "Heavy snow showers"
      95 -> "Thunderstorm"
      96 -> "Thunderstorm with hail"
      99 -> "Thunderstorm with heavy hail"
      _ -> if is_day, do: "Unknown (day)", else: "Unknown (night)"
    end
  end
  defp weather_condition_text(_, is_day) do
    if is_day, do: "Unknown (day)", else: "Unknown (night)"
  end

  defp get_location_name do
    # This could be enhanced to get the actual location name from the weather service
    # For now, we'll return a generic message
    "Current Location"
  end
end
