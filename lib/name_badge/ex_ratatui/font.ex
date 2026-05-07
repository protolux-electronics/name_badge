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
  pixel of the cell. Bits 7–2 hold the 6 cell columns; bits 1–0 are
  always zero (unused).

      iex> bitmap = NameBadge.ExRatatui.Font.glyph(?A)
      iex> byte_size(bitmap)
      8

  ## Source format (5×7 vs 6×8)

  Glyphs are declared as ASCII-art blocks (`#` ink, `.` paper) and
  parsed to bitmaps at compile time. Two source shapes are accepted:

    * **5×7** (5 columns × 7 rows) — the typographic majority. The
      parser implicitly adds a paper column on the right (inter-cell
      spacing) and a paper row at the bottom (inter-line spacing).
      Used for letters, digits, and most punctuation.

    * **6×8** (6 columns × 8 rows) — used for glyphs that need to
      fill the entire cell rectangle to render correctly across cell
      boundaries: box-drawing characters, block elements, full-bleed
      shading. Author controls every pixel.

  ## Coverage

  Currently encoded:

    * Digits `0`–`9`
    * Uppercase `A`–`Z`, lowercase `a`–`z`
    * Space and common ASCII punctuation
    * Light single-line box-drawing: `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼`
    * Block elements: `█ ▀ ▄ ░ ▒ ▓`

  Codepoints outside this set fall back to a visually-distinct hatched
  box so they are obvious in renderings rather than silently blank.
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
    """,
    ?a => """
    .....
    .....
    .###.
    ....#
    .####
    #...#
    .####
    """,
    ?b => """
    #....
    #....
    ####.
    #...#
    #...#
    #...#
    ####.
    """,
    ?c => """
    .....
    .....
    .###.
    #....
    #....
    #....
    .###.
    """,
    ?d => """
    ....#
    ....#
    .####
    #...#
    #...#
    #...#
    .####
    """,
    ?e => """
    .....
    .....
    .###.
    #...#
    #####
    #....
    .###.
    """,
    ?f => """
    ..##.
    .#...
    .###.
    .#...
    .#...
    .#...
    .#...
    """,
    ?g => """
    .....
    .....
    .####
    #...#
    .####
    ....#
    .###.
    """,
    ?h => """
    #....
    #....
    ####.
    #...#
    #...#
    #...#
    #...#
    """,
    ?i => """
    ..#..
    .....
    .##..
    ..#..
    ..#..
    ..#..
    .###.
    """,
    ?j => """
    ....#
    .....
    ...##
    ....#
    ....#
    ....#
    .###.
    """,
    ?k => """
    #....
    #....
    #...#
    #..#.
    ###..
    #..#.
    #...#
    """,
    ?l => """
    .##..
    ..#..
    ..#..
    ..#..
    ..#..
    ..#..
    .###.
    """,
    ?m => """
    .....
    .....
    ##.#.
    #.#.#
    #.#.#
    #...#
    #...#
    """,
    ?n => """
    .....
    .....
    ####.
    #...#
    #...#
    #...#
    #...#
    """,
    ?o => """
    .....
    .....
    .###.
    #...#
    #...#
    #...#
    .###.
    """,
    ?p => """
    .....
    .....
    ####.
    #...#
    ####.
    #....
    #....
    """,
    ?q => """
    .....
    .....
    .####
    #...#
    .####
    ....#
    ....#
    """,
    ?r => """
    .....
    .....
    #.##.
    ##...
    #....
    #....
    #....
    """,
    ?s => """
    .....
    .....
    .####
    #....
    .###.
    ....#
    ####.
    """,
    ?t => """
    .#...
    .#...
    ###..
    .#...
    .#...
    .#...
    ..##.
    """,
    ?u => """
    .....
    .....
    #...#
    #...#
    #...#
    #...#
    .####
    """,
    ?v => """
    .....
    .....
    #...#
    #...#
    #...#
    .#.#.
    ..#..
    """,
    ?w => """
    .....
    .....
    #...#
    #...#
    #.#.#
    #.#.#
    .#.#.
    """,
    ?x => """
    .....
    .....
    #...#
    .#.#.
    ..#..
    .#.#.
    #...#
    """,
    ?y => """
    .....
    .....
    #...#
    #...#
    .####
    ....#
    ####.
    """,
    ?z => """
    .....
    .....
    #####
    ....#
    ..##.
    #....
    #####
    """,
    # Light single-line box-drawing (Unicode U+2500..U+253C). 6×8 so
    # they span the full cell. Vertical sits at column 2; horizontal
    # at row 3.
    0x2500 =>
      """
      ......
      ......
      ......
      ######
      ......
      ......
      ......
      ......
      """,
    0x2502 =>
      """
      ..#...
      ..#...
      ..#...
      ..#...
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    0x250C =>
      """
      ......
      ......
      ......
      ..####
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    0x2510 =>
      """
      ......
      ......
      ......
      ###...
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    0x2514 =>
      """
      ..#...
      ..#...
      ..#...
      ..####
      ......
      ......
      ......
      ......
      """,
    0x2518 =>
      """
      ..#...
      ..#...
      ..#...
      ###...
      ......
      ......
      ......
      ......
      """,
    0x251C =>
      """
      ..#...
      ..#...
      ..#...
      ..####
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    0x2524 =>
      """
      ..#...
      ..#...
      ..#...
      ####..
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    0x252C =>
      """
      ......
      ......
      ......
      ######
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    0x2534 =>
      """
      ..#...
      ..#...
      ..#...
      ######
      ......
      ......
      ......
      ......
      """,
    0x253C =>
      """
      ..#...
      ..#...
      ..#...
      ######
      ..#...
      ..#...
      ..#...
      ..#...
      """,
    # Block elements (Unicode U+2580, U+2584, U+2588, U+2591..U+2593).
    0x2580 =>
      """
      ######
      ######
      ######
      ######
      ......
      ......
      ......
      ......
      """,
    0x2584 =>
      """
      ......
      ......
      ......
      ......
      ######
      ######
      ######
      ######
      """,
    0x2588 =>
      """
      ######
      ######
      ######
      ######
      ######
      ######
      ######
      ######
      """,
    0x2591 =>
      """
      .#..#.
      ......
      #..#..
      ......
      .#..#.
      ......
      #..#..
      ......
      """,
    0x2592 =>
      """
      #.#.#.
      .#.#.#
      #.#.#.
      .#.#.#
      #.#.#.
      .#.#.#
      #.#.#.
      .#.#.#
      """,
    0x2593 =>
      """
      .#####
      #.####
      ##.###
      ###.##
      ####.#
      #####.
      .#####
      #.####
      """
  }

  # Compile-time conversion of each ASCII-art block to an 8-byte
  # binary. Done inline (no helper-function calls) because the module
  # itself isn't fully defined while its attributes are being
  # evaluated.
  #
  # Accepts two source shapes per glyph:
  #
  #   * 5×7 — five columns × seven rows. Each row is right-padded with
  #     a paper column (inter-cell spacing); a blank row is appended
  #     to reach 8 rows total (inter-line spacing).
  #   * 6×8 — six columns × eight rows. Author controls every pixel.
  #     Used for box-drawing and block elements that must fill the
  #     full cell rect.
  @glyphs Map.new(@glyph_data, fn {codepoint, art} ->
            raw_rows = String.split(art, "\n", trim: true)

            row_chars =
              Enum.map(raw_rows, fn line ->
                chars = String.graphemes(line)

                case length(chars) do
                  5 -> chars ++ ["."]
                  6 -> chars
                  n -> raise "glyph #{inspect(codepoint)}: expected 5 or 6 cols per row, got #{n}"
                end
              end)

            rows =
              Enum.map(row_chars, fn six_chars ->
                [b5, b4, b3, b2, b1, b0] =
                  Enum.map(six_chars, fn
                    "#" -> 1
                    "." -> 0
                  end)

                <<b5::1, b4::1, b3::1, b2::1, b1::1, b0::1, 0::1, 0::1>>
              end)

            bitmap =
              case length(rows) do
                7 -> IO.iodata_to_binary([rows, <<0>>])
                8 -> IO.iodata_to_binary(rows)
                n -> raise "glyph #{inspect(codepoint)}: expected 7 or 8 rows, got #{n}"
              end

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
