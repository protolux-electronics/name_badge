defmodule NameBadge.Screen.ExRatatui.Goathi.Art do
  @moduledoc """
  Pure helpers for turning ASCII-art strings into
  `ExRatatui.Widgets.Canvas.Points` structs.

  Lives in its own module so `NameBadge.Screen.ExRatatui.Goathi` can
  evaluate it at compile-time and bake the resulting `%Points{}` into
  module attributes — the goat face never changes between renders, so
  re-parsing the same heredoc 60 times a minute is pure waste.
  """

  alias ExRatatui.Widgets.Canvas.Points

  @doc """
  Walks an ASCII-art string and emits a `%Points{}` carrying one
  coordinate per non-space character. Row 0 of the art lines up with
  `y_origin`; each subsequent row sits one canvas-unit below.
  """
  @spec ascii_to_points(String.t(), number(), number()) :: Points.t()
  def ascii_to_points(art, x_origin, y_origin) when is_binary(art) do
    coords =
      art
      |> String.split("\n")
      |> Enum.with_index()
      |> Enum.flat_map(fn {row_str, row} ->
        row_str
        |> String.graphemes()
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {" ", _col} -> []
          {_char, col} -> [{x_origin + col * 1.0, y_origin - row * 1.0}]
        end)
      end)

    %Points{coords: coords, color: :white}
  end
end
