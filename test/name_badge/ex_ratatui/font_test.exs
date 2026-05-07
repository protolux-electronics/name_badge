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

    test "row 7 is always the inter-line spacer (zero)" do
      for codepoint <- Font.codepoints() do
        <<_top::7-bytes, last>> = Font.glyph(codepoint)
        assert last == 0, "row 7 of glyph #{inspect(codepoint)} must be blank, got #{last}"
      end
    end

    test "bottom two bits of every row are always zero (rightmost column blank)" do
      for codepoint <- Font.codepoints(),
          <<row::8>> <- :binary.bin_to_list(Font.glyph(codepoint)) |> Enum.map(&<<&1>>) do
        assert Bitwise.band(row, 0b11) == 0,
               "glyph #{inspect(codepoint)} has ink in the right-spacer column: row=#{row}"
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
  end

  describe "has_glyph?/1" do
    test "is true for digits, uppercase, and common punctuation" do
      for cp <- Enum.concat([?0..?9, ?A..?Z, [?\s, ?., ?,, ?:, ?+, ?-, ??, ?!]]) do
        assert Font.has_glyph?(cp), "expected glyph for #{[cp]}"
      end
    end

    test "is false for codepoints we haven't encoded yet (lowercase, emoji)" do
      refute Font.has_glyph?(?a)
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
