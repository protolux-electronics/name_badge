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

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware,
  rootfs_overlay: "rootfs_overlay",
  provisioning: "config/provisioning.conf"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1753482945"

config :name_badge,
       :base_url,
       System.get_env("BASE_URL") || raise("environment variable `BASE_URL` was not set")

# Optional: Weather location configuration
# If not set, location will be determined via IP geolocation
# Environment variables WEATHER_LATITUDE and WEATHER_LONGITUDE take precedence
config :name_badge, :weather,
  latitude: 53.56176317072124,
  longitude: 9.985888668967176,
  name: nil

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
