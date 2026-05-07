defmodule NameBadge.ExRatatui.Font do
  @moduledoc """
  Embedded 6×8 monospace bitmap font used to rasterise ex_ratatui cell
  buffers onto the badge's e-ink display.

  Each cell occupies a fixed `#{6} × #{8}` pixel box: a 5×7 glyph plus
  one column of inter-cell spacing on the right and one row of
  inter-line spacing at the bottom. The 5×7 ink area uses a
  hand-encoded ASCII-art declaration that is parsed to bytes at
  compile-time (see `glyph_data/0`).

  ## Glyph format

  `glyph/1` returns an 8-byte binary, one byte per row from top to
  bottom. Within each row, the most-significant bit is the leftmost
  pixel of the cell. Only the top six bits of each byte are
  meaningful; the bottom two are always zero (the rightmost column of
  the cell is the inter-cell spacer). Row 7 is always all zeros (the
  inter-line spacer).

      iex> bitmap = NameBadge.ExRatatui.Font.glyph(?A)
      iex> byte_size(bitmap)
      8

  ## Coverage

  v1 covers digits 0–9, uppercase A–Z, space, and common ASCII
  punctuation — enough for the demo apps that drive the cell-mode
  rendering pipeline. Codepoints outside this set fall back to a
  visually-distinct hatched box so they are obvious in renderings
  rather than silently blank. Lowercase letters and box-drawing glyphs
  are deferred to a follow-up.
  """

  @cell_width 6
  @cell_height 8

  @doc """
  Pixels per cell column. The font is monospace so this is constant.
  """
  @spec cell_width() :: pos_integer()
  def cell_width(), do: @cell_width

  @doc """
  Pixels per cell row. Constant for this monospace font.
  """
  @spec cell_height() :: pos_integer()
  def cell_height(), do: @cell_height

  # ASCII-art glyph definitions. Each entry is `{codepoint, art}` where
  # `art` is exactly 7 lines of 5 characters; `#` marks an ink pixel and
  # `.` marks an empty pixel. The compile-time parser pads each row to
  # 6 columns (rightmost column blank for inter-cell spacing) and
  # appends a blank 8th row (inter-line spacing).
  @glyph_data %{
    ?\s => """
    .....
    .....
    .....
    .....
    .....
    .....
    .....
    """,
    ?! => """
    ..#..
    ..#..
    ..#..
    ..#..
    ..#..
    .....
    ..#..
    """,
    ?" => """
    .#.#.
    .#.#.
    .#.#.
    .....
    .....
    .....
    .....
    """,
    ?# => """
    .#.#.
    .#.#.
    #####
    .#.#.
    #####
    .#.#.
    .#.#.
    """,
    ?$ => """
    ..#..
    .####
    #.#..
    .###.
    ..#.#
    ####.
    ..#..
    """,
    ?% => """
    ##...
    ##..#
    ...#.
    ..#..
    .#...
    #..##
    ...##
    """,
    ?& => """
    .##..
    #..#.
    #..#.
    .##..
    #.#.#
    #..#.
    .##.#
    """,
    ?' => """
    ..#..
    ..#..
    ..#..
    .....
    .....
    .....
    .....
    """,
    ?( => """
    ...#.
    ..#..
    .#...
    .#...
    .#...
    ..#..
    ...#.
    """,
    ?) => """
    .#...
    ..#..
    ...#.
    ...#.
    ...#.
    ..#..
    .#...
    """,
    ?* => """
    .....
    .#.#.
    .###.
    #####
    .###.
    .#.#.
    .....
    """,
    ?+ => """
    .....
    ..#..
    ..#..
    #####
    ..#..
    ..#..
    .....
    """,
    ?, => """
    .....
    .....
    .....
    .....
    .....
    ..#..
    .#...
    """,
    ?- => """
    .....
    .....
    .....
    #####
    .....
    .....
    .....
    """,
    ?. => """
    .....
    .....
    .....
    .....
    .....
    .....
    ..#..
    """,
    ?/ => """
    ....#
    ...#.
    ..#..
    ..#..
    .#...
    #....
    #....
    """,
    ?0 => """
    .###.
    #...#
    #..##
    #.#.#
    ##..#
    #...#
    .###.
    """,
    ?1 => """
    ..#..
    .##..
    ..#..
    ..#..
    ..#..
    ..#..
    .###.
    """,
    ?2 => """
    .###.
    #...#
    ....#
    ...#.
    ..#..
    .#...
    #####
    """,
    ?3 => """
    .###.
    #...#
    ....#
    ..##.
    ....#
    #...#
    .###.
    """,
    ?4 => """
    ...#.
    ..##.
    .#.#.
    #..#.
    #####
    ...#.
    ...#.
    """,
    ?5 => """
    #####
    #....
    ####.
    ....#
    ....#
    #...#
    .###.
    """,
    ?6 => """
    .###.
    #...#
    #....
    ####.
    #...#
    #...#
    .###.
    """,
    ?7 => """
    #####
    ....#
    ...#.
    ..#..
    .#...
    .#...
    .#...
    """,
    ?8 => """
    .###.
    #...#
    #...#
    .###.
    #...#
    #...#
    .###.
    """,
    ?9 => """
    .###.
    #...#
    #...#
    .####
    ....#
    #...#
    .###.
    """,
    ?: => """
    .....
    .....
    ..#..
    .....
    ..#..
    .....
    .....
    """,
    ?; => """
    .....
    .....
    ..#..
    .....
    ..#..
    ..#..
    .#...
    """,
    ?< => """
    ....#
    ...#.
    ..#..
    .#...
    ..#..
    ...#.
    ....#
    """,
    ?= => """
    .....
    .....
    #####
    .....
    #####
    .....
    .....
    """,
    ?> => """
    #....
    .#...
    ..#..
    ...#.
    ..#..
    .#...
    #....
    """,
    ?? => """
    .###.
    #...#
    ....#
    ..##.
    ..#..
    .....
    ..#..
    """,
    ?@ => """
    .###.
    #...#
    #.###
    #.#.#
    #.###
    #....
    .###.
    """,
    ?A => """
    .###.
    #...#
    #...#
    #####
    #...#
    #...#
    #...#
    """,
    ?B => """
    ####.
    #...#
    #...#
    ####.
    #...#
    #...#
    ####.
    """,
    ?C => """
    .###.
    #...#
    #....
    #....
    #....
    #...#
    .###.
    """,
    ?D => """
    ####.
    #...#
    #...#
    #...#
    #...#
    #...#
    ####.
    """,
    ?E => """
    #####
    #....
    #....
    ####.
    #....
    #....
    #####
    """,
    ?F => """
    #####
    #....
    #....
    ####.
    #....
    #....
    #....
    """,
    ?G => """
    .###.
    #...#
    #....
    #.###
    #...#
    #...#
    .###.
    """,
    ?H => """
    #...#
    #...#
    #...#
    #####
    #...#
    #...#
    #...#
    """,
    ?I => """
    .###.
    ..#..
    ..#..
    ..#..
    ..#..
    ..#..
    .###.
    """,
    ?J => """
    ..###
    ...#.
    ...#.
    ...#.
    ...#.
    #..#.
    .##..
    """,
    ?K => """
    #...#
    #..#.
    #.#..
    ##...
    #.#..
    #..#.
    #...#
    """,
    ?L => """
    #....
    #....
    #....
    #....
    #....
    #....
    #####
    """,
    ?M => """
    #...#
    ##.##
    #.#.#
    #.#.#
    #...#
    #...#
    #...#
    """,
    ?N => """
    #...#
    #...#
    ##..#
    #.#.#
    #..##
    #...#
    #...#
    """,
    ?O => """
    .###.
    #...#
    #...#
    #...#
    #...#
    #...#
    .###.
    """,
    ?P => """
    ####.
    #...#
    #...#
    ####.
    #....
    #....
    #....
    """,
    ?Q => """
    .###.
    #...#
    #...#
    #...#
    #.#.#
    #..#.
    .##.#
    """,
    ?R => """
    ####.
    #...#
    #...#
    ####.
    #.#..
    #..#.
    #...#
    """,
    ?S => """
    .###.
    #...#
    #....
    .###.
    ....#
    #...#
    .###.
    """,
    ?T => """
    #####
    ..#..
    ..#..
    ..#..
    ..#..
    ..#..
    ..#..
    """,
    ?U => """
    #...#
    #...#
    #...#
    #...#
    #...#
    #...#
    .###.
    """,
    ?V => """
    #...#
    #...#
    #...#
    #...#
    #...#
    .#.#.
    ..#..
    """,
    ?W => """
    #...#
    #...#
    #...#
    #.#.#
    #.#.#
    #.#.#
    .#.#.
    """,
    ?X => """
    #...#
    #...#
    .#.#.
    ..#..
    .#.#.
    #...#
    #...#
    """,
    ?Y => """
    #...#
    #...#
    #...#
    .#.#.
    ..#..
    ..#..
    ..#..
    """,
    ?Z => """
    #####
    ....#
    ...#.
    ..#..
    .#...
    #....
    #####
    """,
    ?[ => """
    .###.
    .#...
    .#...
    .#...
    .#...
    .#...
    .###.
    """,
    ?\\ => """
    #....
    #....
    .#...
    ..#..
    ..#..
    ...#.
    ....#
    """,
    ?] => """
    .###.
    ...#.
    ...#.
    ...#.
    ...#.
    ...#.
    .###.
    """,
    ?^ => """
    ..#..
    .#.#.
    #...#
    .....
    .....
    .....
    .....
    """,
    ?_ => """
    .....
    .....
    .....
    .....
    .....
    .....
    #####
    """
  }

  # Compile-time conversion of each ASCII-art block to an 8-byte
  # binary. Done inline (no helper-function calls) because the module
  # itself isn't fully defined while its attributes are being
  # evaluated.
  @glyphs Map.new(@glyph_data, fn {codepoint, art} ->
            rows =
              art
              |> String.split("\n", trim: true)
              |> Enum.map(fn line ->
                chars = String.graphemes(line)
                5 = length(chars)

                [b5, b4, b3, b2, b1, b0] =
                  Enum.map(chars ++ ["."], fn
                    "#" -> 1
                    "." -> 0
                  end)

                <<b5::1, b4::1, b3::1, b2::1, b1::1, b0::1, 0::1, 0::1>>
              end)

            7 = length(rows)
            bitmap = IO.iodata_to_binary([rows, <<0>>])
            8 = byte_size(bitmap)
            {codepoint, bitmap}
          end)

  @missing_glyph <<
    0b10101010,
    0b01010100,
    0b10101010,
    0b01010100,
    0b10101010,
    0b01010100,
    0b10101010,
    0b00000000
  >>

  @doc """
  Returns the 8-byte bitmap for the glyph at `codepoint`.

  Each byte encodes one row from top to bottom. Within a row the
  most-significant bit is the leftmost pixel of the cell; bits 1 and 0
  are always zero (rightmost column is the inter-cell spacer). Row 7
  is always zero (the inter-line spacer).

  Codepoints with no encoded glyph return a hatched placeholder so
  they render as a visibly-distinct "missing" cell rather than
  silently blank.
  """
  @spec glyph(integer()) :: <<_::64>>
  def glyph(codepoint) when is_integer(codepoint) do
    Map.get(@glyphs, codepoint, @missing_glyph)
  end

  @doc """
  Returns `true` if `codepoint` has a hand-encoded glyph in the font.
  Useful for callers that want to substitute their own placeholder for
  unsupported characters.
  """
  @spec has_glyph?(integer()) :: boolean()
  def has_glyph?(codepoint) when is_integer(codepoint) do
    Map.has_key?(@glyphs, codepoint)
  end

  @doc """
  Returns the list of codepoints with hand-encoded glyphs, sorted
  ascending. Primarily for tests and tooling.
  """
  @spec codepoints() :: [integer()]
  def codepoints(), do: @glyphs |> Map.keys() |> Enum.sort()
end
