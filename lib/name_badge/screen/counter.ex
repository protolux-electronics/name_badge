defmodule NameBadge.Screen.Counter do
  @moduledoc """
  Menu-facing wrapper around `NameBadge.Screen.ExRatatui.Counter` —
  hosts the Counter `ExRatatui.App` through the
  `NameBadge.Screen.ExRatatui` adapter, using the adapter's default
  A/B/A-long key map.
  """

  use NameBadge.Screen.ExRatatui, app: NameBadge.Screen.ExRatatui.Counter
end
