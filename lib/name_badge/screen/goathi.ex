defmodule NameBadge.Screen.Goathi do
  @moduledoc """
  Menu-facing wrapper around `NameBadge.Screen.ExRatatui.Goathi` —
  hosts the animated greeting through `NameBadge.Screen.ExRatatui`
  with the adapter's default A/B/A-long key map.
  """

  use NameBadge.Screen.ExRatatui, app: NameBadge.Screen.ExRatatui.Goathi
end
