defmodule NameBadge.Screen.Stats do
  @moduledoc """
  Menu-facing wrapper around `NameBadge.Screen.ExRatatui.Stats` —
  hosts the BEAM system monitor through `NameBadge.Screen.ExRatatui`
  with the adapter's default A/B/A-long key map.
  """

  use NameBadge.Screen.ExRatatui, app: NameBadge.Screen.ExRatatui.Stats
end
