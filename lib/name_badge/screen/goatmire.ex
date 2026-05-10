defmodule NameBadge.Screen.Goatmire do
  @moduledoc """
  Menu-facing wrapper around `NameBadge.Screen.ExRatatui.Goatmire` —
  hosts the animated greeting through `NameBadge.Screen.ExRatatui`
  with the adapter's default A/B/A-long key map.
  """

  use NameBadge.Screen.ExRatatui, app: NameBadge.Screen.ExRatatui.Goatmire
end
