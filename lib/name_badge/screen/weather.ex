defmodule NameBadge.Screen.Weather do
  @moduledoc """
  Weather screen with two views:
  - Current: today's weather with date, location, temperature, condition, wind.
  - Forecast: 7-day columnar forecast showing day names, temperatures, conditions, and wind.

  Button A: Refresh weather data.
  Button B: Toggle between Current and Forecast views.
  Long press B: Navigate back (handled by Screen behaviour).
  """

  use NameBadge.Screen

  require Logger

  @impl NameBadge.Screen
  def render(%{weather: nil, loading: true}) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Weather

    #v(16pt)

    #align(center + horizon)[
      #text(size: 24pt)[Loading weather data...]

      #text(size: 12pt)[
        Thanks to Tim Pritlove and Pepe for contributing this screen!
      ]
    ]
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

  def render(%{view: :forecast} = assigns), do: render_forecast(assigns)

  def render(%{weather: weather, location: location}) do
    temp_display = format_temperature(weather.temperature, weather.temperature_unit)
    condition = weather_condition_text(weather.weather_code, weather.is_day)
    wind_display = format_wind_speed(weather.wind_speed, weather.wind_speed_unit)
    date_display = format_current_date()

    """
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Weather

    #v(12pt)

    #align(center)[
      #stack(dir: ttb, spacing: 12pt,

        // Date
        text(size: 16pt, weight: 600)[#{date_display}],

        // Location
        text(size: 14pt, style: "italic")[#{location || "Unknown Location"}],

        // Temperature (main display)
        text(size: 48pt, weight: 600)[#{temp_display}],

        // Weather condition
        text(size: 18pt)[#{condition}],

        // Wind speed
        text(size: 14pt)[Wind: #{wind_display}],

        // Last updated
        text(size: 12pt, fill: gray)[#{format_last_updated(weather.timestamp)}]
      )
    ]
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    # Get initial weather data, forecast and location
    weather = NameBadge.Weather.get_current_weather()
    forecast = NameBadge.Weather.get_forecast()
    location = NameBadge.Weather.get_location_name()

    screen =
      case weather do
        nil ->
          screen
          |> assign(
            weather: nil,
            loading: true,
            location: location,
            forecast: forecast,
            view: :current
          )
          |> assign(button_hints: %{a: "Refresh", b: "Forecast"})

        weather_data ->
          screen
          |> assign(
            weather: weather_data,
            loading: false,
            location: location,
            forecast: forecast,
            view: :current
          )
          |> assign(button_hints: %{a: "Refresh", b: "Forecast"})
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
      |> assign(weather: nil, loading: true, error: nil, view: :current)
      |> assign(button_hints: %{a: "Refresh", b: "Forecast"})

    # Schedule a check for updated data in 2 seconds
    Process.send_after(self(), :check_weather_update, 2_000)

    {:noreply, screen}
  end

  def handle_button(:button_2, :single_press, screen) do
    # Toggle between current weather and 7-day forecast views
    case screen.assigns.view do
      :current ->
        screen =
          screen
          |> assign(view: :forecast)
          |> assign(button_hints: %{a: "Refresh", b: "Current"})

        {:noreply, screen}

      :forecast ->
        screen =
          screen
          |> assign(view: :current)
          |> assign(button_hints: %{a: "Refresh", b: "Forecast"})

        {:noreply, screen}
    end
  end

  def handle_button(_, _, screen), do: {:noreply, screen}

  @impl NameBadge.Screen
  def handle_info(:check_weather_update, screen) do
    weather = NameBadge.Weather.get_current_weather()
    forecast = NameBadge.Weather.get_forecast()
    location = NameBadge.Weather.get_location_name()

    screen =
      case weather do
        nil ->
          assign(screen,
            weather: nil,
            loading: false,
            error: "Unable to fetch weather data",
            location: location,
            forecast: forecast
          )

        weather_data ->
          assign(screen,
            weather: weather_data,
            loading: false,
            error: nil,
            location: location,
            forecast: forecast
          )
      end

    {:noreply, screen}
  end

  # ── Forecast view ──────────────────────────────────────────────────────

  defp render_forecast(%{forecast: forecast, location: location}) do
    date_range = format_date_range(forecast)

    # Row 1: Day name abbreviations (Mo, Tu, We, ...)
    day_names =
      forecast
      |> Enum.map(fn day -> "[#text(size: 16pt, weight: 700)[#{format_day_abbr(day.date)}]]" end)
      |> Enum.join(", ")

    # Row 2: Temperatures (min/max)
    temps =
      forecast
      |> Enum.map(fn day ->
        temp_unit = day.temperature_unit

        "[#text(size: 12pt)[#{round(day.min_temp)}#{temp_unit}] #linebreak() #text(size: 12pt)[#{round(day.max_temp)}#{temp_unit}]]"
      end)
      |> Enum.join(", ")

    # Row 3: Weather conditions (short text, clipped to cell width)
    conditions =
      forecast
      |> Enum.map(fn day ->
        "[#box(width: 100%, clip: true)[#text(size: 12pt)[#{weather_condition_short(day.weather_code)}]]]"
      end)
      |> Enum.join(", ")

    # Row 4: Wind speeds (number+unit no space, single row)
    winds =
      forecast
      |> Enum.map(fn day ->
        "[#text(size: 9pt)[#{round(day.max_wind)}#{day.wind_speed_unit}]]"
      end)
      |> Enum.join(", ")

    """
    #show heading: set text(font: "Silkscreen", size: 36pt, weight: 400, tracking: -4pt)

    = Forecast

    #v(2pt)

    #align(center)[
      #text(size: 14pt, style: "italic")[#{location || "Unknown Location"}]
      #v(-4pt)
      #text(size: 12pt)[#{date_range}]
    ]

    #v(2pt)
    

    #table(
      columns: (1fr,) * 7,
      align: center,
      inset: 5pt,
      stroke: 0.5pt + gray,
      #{day_names},
      #{temps},
      #{conditions},
      #{winds}
    )
    """
  end

  # ── Date helpers ───────────────────────────────────────────────────────

  defp format_current_date do
    Date.utc_today()
    |> Calendar.strftime("%A, %B %d")
  end

  defp format_date_range([]) do
    ""
  end

  defp format_date_range(forecast) do
    first = List.first(forecast)
    last = List.last(forecast)

    first_date = Date.from_iso8601!(first.date)
    last_date = Date.from_iso8601!(last.date)

    if first_date.month == last_date.month do
      "#{first_date.day}-#{last_date.day} #{Calendar.strftime(first_date, "%B")}"
    else
      "#{Calendar.strftime(first_date, "%b %d")} - #{Calendar.strftime(last_date, "%b %d")}"
    end
  end

  defp format_day_abbr(date_string) when is_binary(date_string) do
    date = Date.from_iso8601!(date_string)
    Calendar.strftime(date, "%a")
  end

  # ── Temperature / wind formatting ─────────────────────────────────────

  defp format_temperature(temp, unit) when is_number(temp) and is_binary(unit) do
    "#{round(temp)}#{unit}"
  end

  defp format_temperature(temp, _unit) when is_number(temp) do
    "#{round(temp)}°C"
  end

  defp format_temperature(_, _), do: "N/A"

  defp format_wind_speed(speed, unit) when is_number(speed) and is_binary(unit) do
    "#{round(speed)} #{unit}"
  end

  defp format_wind_speed(speed, _unit) when is_number(speed) do
    "#{round(speed)} km/h"
  end

  defp format_wind_speed(_, _), do: "N/A"

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

      _ ->
        "Recently"
    end
  end

  defp format_last_updated(_), do: "Recently"

  # ── Weather condition texts ───────────────────────────────────────────

  defp weather_condition_short(code) when is_number(code) do
    case code do
      0 -> "Clear"
      1 -> "Clear"
      2 -> "Clouds"
      3 -> "Ovcst"
      45 -> "Fog"
      48 -> "Fog"
      51 -> "Drzzl"
      53 -> "Drzzl"
      55 -> "Drzzl"
      56 -> "FrzDr"
      57 -> "FrzDr"
      61 -> "Rain"
      63 -> "Rain"
      65 -> "Rain+"
      66 -> "FrzRn"
      67 -> "FrzRn"
      71 -> "Snow"
      73 -> "Snow"
      75 -> "Snow+"
      77 -> "Snow"
      80 -> "Shwrs"
      81 -> "Shwrs"
      82 -> "Shwrs"
      85 -> "SnShw"
      86 -> "SnShw"
      95 -> "Storm"
      96 -> "Storm"
      99 -> "Storm"
      _ -> "N/A"
    end
  end

  defp weather_condition_short(_code), do: "N/A"

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
end
