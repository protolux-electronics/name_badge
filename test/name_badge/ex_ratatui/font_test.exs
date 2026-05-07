defmodule NameBadge.ExRatatui.FontTest do
  use ExUnit.Case, async: true

  alias NameBadge.ExRatatui.Font

  describe "cell dimensions" do
    test "are 6×8" do
      assert Font.cell_width() == 6
      assert Font.cell_height() == 8
    end
  end

  describe "glyph/1" do
    test "returns 8 bytes for an encoded codepoint" do
      assert <<_::64>> = Font.glyph(?A)
      assert byte_size(Font.glyph(?A)) == 8
    end

    test "returns 8 bytes for an unencoded codepoint (placeholder)" do
      # Heart emoji has no encoded glyph; still must be safe to
      # rasterise.
      assert byte_size(Font.glyph(0x2764)) == 8
    end

    test "bottom two bits of every row are unused padding (always zero)" do
      # Bits 7..2 hold the 6 cell columns; bits 1..0 are always zero
      # regardless of source format (5×7 or 6×8). This is a structural
      # invariant of the bitmap encoding itself.
      for codepoint <- Font.codepoints(),
          <<row::8>> <- :binary.bin_to_list(Font.glyph(codepoint)) |> Enum.map(&<<&1>>) do
        assert Bitwise.band(row, 0b11) == 0,
               "glyph #{inspect(codepoint)} has unexpected ink in the unused bottom 2 bits: row=#{row}"
      end
    end

    test "?A renders the canonical capital-A bitmap" do
      # .###.    →  0b01110000
      # #...#    →  0b10001000
      # #...#    →  0b10001000
      # #####    →  0b11111000
      # #...#    →  0b10001000
      # #...#    →  0b10001000
      # #...#    →  0b10001000
      # blank    →  0b00000000
      assert Font.glyph(?A) ==
               <<0b01110000, 0b10001000, 0b10001000, 0b11111000, 0b10001000, 0b10001000,
                 0b10001000, 0b00000000>>
    end

    test "?\\s (space) is entirely blank" do
      assert Font.glyph(?\s) == <<0, 0, 0, 0, 0, 0, 0, 0>>
    end

    test "?0 is encoded" do
      assert Font.has_glyph?(?0)
      refute Font.glyph(?0) == <<0, 0, 0, 0, 0, 0, 0, 0>>
    end

    test "─ (U+2500) fills row 3 across all 6 cell columns" do
      # 6×8 source: row 3 is `######`, all other rows are blank. The
      # rendered byte for row 3 has bits 7..2 set and bits 1..0 zero.
      assert Font.glyph(0x2500) ==
               <<0, 0, 0, 0b11111100, 0, 0, 0, 0>>
    end

    test "│ (U+2502) fills column 2 across all 8 rows (continuous vertical)" do
      expected_row = <<0b00100000>>
      assert Font.glyph(0x2502) == :binary.copy(expected_row, 8)
    end

    test "█ (U+2588) is fully inked" do
      assert Font.glyph(0x2588) == :binary.copy(<<0b11111100>>, 8)
    end
  end

  describe "has_glyph?/1" do
    test "is true for digits, uppercase, lowercase, and common punctuation" do
      for cp <- Enum.concat([?0..?9, ?A..?Z, ?a..?z, [?\s, ?., ?,, ?:, ?+, ?-, ??, ?!]]) do
        assert Font.has_glyph?(cp), "expected glyph for #{[cp]}"
      end
    end

    test "is true for the light single-line box-drawing set" do
      box = [
        0x2500,
        0x2502,
        0x250C,
        0x2510,
        0x2514,
        0x2518,
        0x251C,
        0x2524,
        0x252C,
        0x2534,
        0x253C
      ]

      for cp <- box do
        assert Font.has_glyph?(cp), "expected glyph for U+#{Integer.to_string(cp, 16)}"
      end
    end

    test "is true for the basic block elements" do
      blocks = [0x2580, 0x2584, 0x2588, 0x2591, 0x2592, 0x2593]

      for cp <- blocks do
        assert Font.has_glyph?(cp), "expected glyph for U+#{Integer.to_string(cp, 16)}"
      end
    end

    test "is false for codepoints we haven't encoded (emoji)" do
      refute Font.has_glyph?(0x2764)
    end
  end

  describe "codepoints/0" do
    test "returns at least the Counter demo's character set" do
      needed = Enum.concat([?0..?9, ?A..?Z, [?\s, ?:, ?+, ?-]])
      have = MapSet.new(Font.codepoints())

      for cp <- needed do
        assert cp in have, "Counter demo needs #{[cp]} (#{cp}) but it isn't encoded"
      end
    end

    test "is sorted" do
      cps = Font.codepoints()
      assert cps == Enum.sort(cps)
    end
  end
end
