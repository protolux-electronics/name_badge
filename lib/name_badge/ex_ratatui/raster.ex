defmodule NameBadge.ExRatatui.Raster do
  @moduledoc """
  Rasterises an `ExRatatui.CellSession` cell buffer into a 400×300
  grayscale image suitable for `NameBadge.Display.render_png/2`.

  Holds an internal cell map keyed by `{col, row}`. Snapshots replace
  the map outright; diffs merge into it so successive renders only pay
  for what actually changed.

  ## Pipeline

      Raster.new()
      |> Raster.put_snapshot(snapshot)   # initial paint
      |> Raster.apply_diff(diff)         # streaming update
      |> Raster.to_png()                 # 400×300 grayscale PNG

  The resulting PNG is fed unchanged to `NameBadge.Display.render_png/2`,
  which already handles grayscale → 1bpp threshold → SPI blit.

  ## Cell to pixel layout

  The font's `#{6} × #{8}` cell, when tiled across a 400×300 canvas,
  fits a #{div(400, 6)} × #{div(300, 8)} grid (400 / 6 = 66 with 4
  unused pixels on the right; 300 / 8 = 37 with 4 unused pixels at the
  bottom). The unused strip stays paper-white. Cell sessions should be
  constructed at this grid size — see `grid_size/0`.

  ## Style support

  The 1-bit display has no concept of color, so any non-default
  `bg` color or the `:reversed` modifier collapses to "this cell is
  inverted": the glyph paints as paper on an ink background, instead
  of ink on paper. The `fg` color is otherwise ignored — there is
  only ink. Other modifiers (bold, italic, underlined, …) are
  ignored. `:skip` cells render as paper.

  | Cell shape                                      | Pixels        |
  | ----------------------------------------------- | ------------- |
  | `bg: :reset`, no `:reversed`                    | ink-on-paper  |
  | `bg: <any non-`:reset`>`, or `:reversed` in mods| paper-on-ink  |
  | `:skip: true`                                   | all paper     |

  Bold-as-double-strike, underline-as-bottom-row, and grayscale `fg`
  / `bg` mappings are deferred until a demo needs them.
  """

  import Bitwise

  alias ExRatatui.CellSession.{Cell, Diff, Snapshot}
  alias NameBadge.ExRatatui.Font

  @display_width 400
  @display_height 300
  @paper 255
  @ink 0

  @cell_w Font.cell_width()
  @cell_h Font.cell_height()
  @grid_cols div(@display_width, @cell_w)
  @grid_rows div(@display_height, @cell_h)

  defstruct cells: %{}

  @type t :: %__MODULE__{cells: %{{non_neg_integer(), non_neg_integer()} => Cell.t()}}

  @doc """
  Returns a fresh rasteriser with no cells (the canvas reads as
  uniform paper).
  """
  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @doc """
  Cell-grid dimensions that fit on the badge display, as
  `{cols, rows}`. Use these when constructing the `ExRatatui.CellSession`.
  """
  @spec grid_size() :: {pos_integer(), pos_integer()}
  def grid_size(), do: {@grid_cols, @grid_rows}

  @doc """
  Pixel dimensions of the rasterised image, as `{width, height}`.
  """
  @spec display_size() :: {pos_integer(), pos_integer()}
  def display_size(), do: {@display_width, @display_height}

  @doc """
  Replaces the rasteriser's cell map with the snapshot's cells.

  Use after an initial `take_cells/1`, after a resize, or whenever the
  caller wants to discard accumulated diff state.
  """
  @spec put_snapshot(t(), Snapshot.t()) :: t()
  def put_snapshot(%__MODULE__{} = r, %Snapshot{cells: cells}) do
    %{r | cells: index(cells)}
  end

  @doc """
  Merges a diff's ops into the rasteriser's cell map.

  Cells not mentioned in the diff retain their prior content. The
  caller is responsible for handling the "full payload after resize"
  case (`length(ops) == width * height`); from the rasteriser's point
  of view that's just a diff that happens to cover everything.
  """
  @spec apply_diff(t(), Diff.t()) :: t()
  def apply_diff(%__MODULE__{cells: existing} = r, %Diff{ops: ops}) do
    %{r | cells: Map.merge(existing, index(ops))}
  end

  @doc """
  Renders the current cell map to a 400×300 grayscale PNG, ready to
  hand to `NameBadge.Display.render_png/2`.
  """
  @spec to_png(t()) :: binary()
  def to_png(%__MODULE__{} = r) do
    r
    |> to_grayscale()
    |> Dither.from_raw!(@display_width, @display_height)
    |> Dither.encode!()
  end

  @doc """
  Renders the current cell map to a flat 400×300 row-major grayscale
  binary (one byte per pixel, 0 = ink, 255 = paper). Mostly useful for
  tests; production callers want `to_png/1`.
  """
  @spec to_grayscale(t()) :: binary()
  def to_grayscale(%__MODULE__{cells: cells}) do
    Enum.reduce(0..(@display_height - 1), [], fn y, acc ->
      cell_row = div(y, @cell_h)
      sub_y = rem(y, @cell_h)

      pixel_row =
        Enum.map(0..(@grid_cols - 1), fn cx ->
          cell_pixel_row(Map.get(cells, {cx, cell_row}), sub_y)
        end)

      [acc, pixel_row, paper_padding(:right)]
    end)
    |> IO.iodata_to_binary()
  end

  @paper_cell_row :binary.copy(<<@paper>>, @cell_w)
  @paper_right_padding :binary.copy(<<@paper>>, @display_width - @grid_cols * @cell_w)

  defp paper_padding(:right), do: @paper_right_padding

  defp cell_pixel_row(nil, _sub_y), do: @paper_cell_row
  defp cell_pixel_row(%Cell{skip: true}, _sub_y), do: @paper_cell_row

  defp cell_pixel_row(%Cell{symbol: symbol} = cell, sub_y) do
    byte =
      symbol
      |> codepoint_of()
      |> Font.glyph()
      |> :binary.at(sub_y)

    {ink, paper} = ink_and_paper(cell)

    Enum.map(0..(@cell_w - 1), fn i ->
      case byte >>> (7 - i) &&& 1 do
        1 -> ink
        0 -> paper
      end
    end)
    |> :binary.list_to_bin()
  end

  # Returns the {ink_byte, paper_byte} pair to use for a cell. On the
  # 1-bit e-ink display, "color" collapses to "are we inverted?" — a
  # cell with a non-default bg or the `:reversed` modifier paints
  # paper glyphs on an ink background; everything else paints the
  # other way around.
  defp ink_and_paper(%Cell{bg: bg, modifiers: modifiers}) do
    if inverted?(bg, modifiers) do
      {@paper, @ink}
    else
      {@ink, @paper}
    end
  end

  defp inverted?(:reset, modifiers), do: :reversed in modifiers
  defp inverted?(_bg, _modifiers), do: true

  defp codepoint_of(""), do: ?\s

  defp codepoint_of(symbol) when is_binary(symbol) do
    case String.to_charlist(symbol) do
      [cp | _] -> cp
      [] -> ?\s
    end
  end

  defp index(cells) do
    Map.new(cells, fn %Cell{col: c, row: r} = cell -> {{c, r}, cell} end)
  end
end
