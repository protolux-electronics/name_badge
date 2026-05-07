defmodule NameBadge.ExRatatui.RasterTest do
  use ExUnit.Case, async: true

  alias ExRatatui.CellSession.{Cell, Diff, Snapshot}
  alias NameBadge.ExRatatui.Raster

  describe "grid_size/0 and display_size/0" do
    test "match the badge display" do
      assert Raster.display_size() == {400, 300}
      # 400 / 6 = 66 (4 px right margin); 300 / 8 = 37 (4 px bottom margin).
      assert Raster.grid_size() == {66, 37}
    end
  end

  describe "to_grayscale/1" do
    test "an empty rasteriser produces a uniform paper canvas" do
      bin = Raster.new() |> Raster.to_grayscale()

      assert byte_size(bin) == 400 * 300
      assert :binary.copy(<<255>>, 400 * 300) == bin
    end

    test "a snapshot with one ink cell paints exactly that cell's glyph" do
      raster =
        Raster.new()
        |> Raster.put_snapshot(snapshot([cell(0, 0, "A")]))

      bin = Raster.to_grayscale(raster)
      assert byte_size(bin) == 400 * 300

      # The 'A' glyph's first row is `.###.` → pixels (1,0), (2,0), (3,0)
      # are ink; (0,0), (4,0), (5,0) are paper. Row stride is 400 bytes.
      assert byte_at(bin, 0, 0) == 255
      assert byte_at(bin, 1, 0) == 0
      assert byte_at(bin, 2, 0) == 0
      assert byte_at(bin, 3, 0) == 0
      assert byte_at(bin, 4, 0) == 255
      assert byte_at(bin, 5, 0) == 255

      # Row 7 is the inter-line spacer — must be paper across the whole cell.
      for x <- 0..5 do
        assert byte_at(bin, x, 7) == 255
      end

      # Cell at (1, 0) wasn't painted — must be entirely paper.
      for x <- 6..11, y <- 0..7 do
        assert byte_at(bin, x, y) == 255,
               "expected paper at (#{x}, #{y}), got #{byte_at(bin, x, y)}"
      end
    end

    test "skip cells render as paper" do
      raster =
        Raster.new()
        |> Raster.put_snapshot(snapshot([%{cell(0, 0, "A") | skip: true}]))

      bin = Raster.to_grayscale(raster)

      for x <- 0..5, y <- 0..7 do
        assert byte_at(bin, x, y) == 255
      end
    end

    test "right and bottom margins are paper (canvas is wider than the grid)" do
      # Fill row 0 with 'A' across every cell column. The 4 unused
      # right-edge pixels (cols 396..399 in pixel space) must stay paper.
      cells = for col <- 0..(elem(Raster.grid_size(), 0) - 1), do: cell(col, 0, "A")

      bin =
        Raster.new()
        |> Raster.put_snapshot(snapshot(cells))
        |> Raster.to_grayscale()

      for x <- 396..399, y <- 0..7 do
        assert byte_at(bin, x, y) == 255
      end

      # Bottom 4 px (rows 296..299) are below the cell grid.
      for x <- 0..399, y <- 296..299 do
        assert byte_at(bin, x, y) == 255
      end
    end
  end

  describe "apply_diff/2" do
    test "merges into the existing cell map without disturbing other cells" do
      base =
        Raster.new()
        |> Raster.put_snapshot(snapshot([cell(0, 0, "A"), cell(1, 0, "B")]))

      updated = Raster.apply_diff(base, diff([cell(0, 0, "C")]))
      bin = Raster.to_grayscale(updated)

      # Cell (1, 0) at pixel (6..11, 0..7) still shows 'B'. 'B's top
      # row is `####.` so pixels (6..9, 0) are ink and (10, 0) is paper.
      assert byte_at(bin, 6, 0) == 0
      assert byte_at(bin, 7, 0) == 0
      assert byte_at(bin, 8, 0) == 0
      assert byte_at(bin, 9, 0) == 0
      assert byte_at(bin, 10, 0) == 255

      # Cell (0, 0) was overwritten with 'C': top row `.###.`, so pixels
      # (1..3, 0) are ink and (0, 0) and (4, 0) are paper.
      assert byte_at(bin, 0, 0) == 255
      assert byte_at(bin, 1, 0) == 0
      assert byte_at(bin, 4, 0) == 255
    end
  end

  describe "to_png/1" do
    test "produces a non-empty PNG that decodes back to the same dimensions" do
      png =
        Raster.new()
        |> Raster.put_snapshot(snapshot([cell(0, 0, "A")]))
        |> Raster.to_png()

      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = png

      ref = Dither.decode!(png)
      raw = ref |> Dither.grayscale!() |> Dither.to_raw!()
      assert byte_size(raw) == 400 * 300
    end
  end

  defp cell(col, row, symbol) do
    %Cell{col: col, row: row, symbol: symbol, fg: :reset, bg: :reset, modifiers: [], skip: false}
  end

  defp snapshot(cells) do
    {cols, rows} = Raster.grid_size()
    %Snapshot{width: cols, height: rows, cells: cells}
  end

  defp diff(ops) do
    {cols, rows} = Raster.grid_size()
    %Diff{width: cols, height: rows, ops: ops}
  end

  defp byte_at(canvas, x, y) when x in 0..399 and y in 0..299 do
    :binary.at(canvas, y * 400 + x)
  end
end
