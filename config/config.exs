# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

# set the time zone database
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :name_badge, :timezone, "Europe/Stockholm"

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware,
  rootfs_overlay: "rootfs_overlay",
  provisioning: "config/provisioning.conf",
  mksquashfs_flags: ["-noI", "-noId", "-noD", "-noF", "-noX"]

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1753482945"

device_setup_url =
  System.get_env("DEVICE_SETUP_URL") ||
    raise "System environment variable `DEVICE_SETUP_URL` was not set. Use value `goatmire.fly.dev`, or set up your own server from the repo at https://github.com/protolux-electronics/goatmire"

config :name_badge, :device_setup_url, device_setup_url

# Optional: Calendar sync via iCal secret address (read-only)
# Set CALENDAR_URL to your Google Calendar secret iCal address before building.
# Set CALENDAR_REFRESH_INTERVAL to customize the refresh interval in milliseconds (default: 5 min).
# If CALENDAR_URL is not set, the calendar feature is entirely disabled.
calendar_url =
  System.get_env("CALENDAR_URL", "http://pirate.monkeyness.com/calendars/Moons-Seasons.ics")

if calendar_url do
  config :name_badge, :calendar,
    url: calendar_url,
    refresh_interval:
      (System.get_env("CALENDAR_REFRESH_INTERVAL") || "30")
      |> String.to_integer()
      |> :timer.minutes()
end

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
