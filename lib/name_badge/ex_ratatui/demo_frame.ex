defmodule NameBadge.ExRatatui.DemoFrame do
  @moduledoc """
  Shared chrome for the badge's `ExRatatui.App` demos.

  Every demo lays out the same way: an outer `Block` titled
  ` ex_ratatui · <demo> ` covers all but the bottom row, and a
  single-row hint strip at the very bottom carries reverse-video
  key chips next to plain action labels. Centralising those rects
  here keeps the screens visually consistent and means individual
  demos only have to position their own content.

  ## Usage

      {block, block_rect, content_rect, hint_rect} = DemoFrame.layout("counter", frame)

      [
        {block, block_rect},
        {my_content_widget, content_rect},
        {DemoFrame.hint([
           {" A ", :chip}, {" +1   ", :label},
           {" A long ", :chip}, {" reset", :label}
         ]), hint_rect}
      ]
  """

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Paragraph}

  @chip_style %Style{modifiers: [:reversed]}

  @typedoc "Hint segments — `:chip` for reverse-video keys, `:label` for plain action text."
  @type hint_segment :: {String.t(), :chip | :label}

  @doc """
  Builds the demo chrome for a frame. Returns
  `{block_widget, block_rect, content_rect, hint_rect}`:

    * `block_widget` — the outer `%Block{}` titled
      ` ex_ratatui · <title> ` with full borders.
    * `block_rect` — the outer rect that pairs with `block_widget`.
      Spans `frame.width` × `frame.height - 2` so the bottom row
      stays free for the hint strip.
    * `content_rect` — the inner rect inside the block borders
      (`block_rect` shrunk by 1 cell on each side). Use this to
      position content widgets.
    * `hint_rect` — the bottom-most row, padded 2 cells in from each
      side, sized for a single-line `Paragraph`.
  """
  @typedoc "Anything carrying `width` and `height` — both `%Rect{}` and `%ExRatatui.Frame{}` qualify."
  @type sized :: %{
          :width => non_neg_integer(),
          :height => non_neg_integer(),
          optional(any()) => any()
        }

  @spec layout(String.t(), sized()) :: {Block.t(), Rect.t(), Rect.t(), Rect.t()}
  def layout(title, %{width: width, height: height})
      when is_binary(title) and is_integer(width) and is_integer(height) do
    block_rect = %Rect{x: 0, y: 0, width: width, height: height - 2}

    content_rect = %Rect{
      x: block_rect.x + 1,
      y: block_rect.y + 1,
      width: block_rect.width - 2,
      height: block_rect.height - 2
    }

    hint_rect = %Rect{
      x: 2,
      y: height - 1,
      width: width - 4,
      height: 1
    }

    {title_block(title), block_rect, content_rect, hint_rect}
  end

  @doc """
  Returns the standard outer block on its own — the same `%Block{}`
  `layout/2` ships back in the tuple. Useful when the demo's main
  widget is a `Canvas`/`Sparkline`/etc that takes its own `:block`
  field instead of pairing the block with a separate rect.
  """
  @spec title_block(String.t()) :: Block.t()
  def title_block(title) when is_binary(title) do
    %Block{title: " ex_ratatui - #{title} ", borders: [:all]}
  end

  @doc """
  Returns a `%Rect{}` of `height` rows vertically centered inside
  `parent`, full-width within it. Use this when a demo wants to
  drop a content row (or a small block) in the middle of the
  content area instead of stacking it at the top.
  """
  @spec center_row(Rect.t(), pos_integer()) :: Rect.t()
  def center_row(%Rect{} = parent, height) when height >= 1 and height <= parent.height do
    y_offset = div(parent.height - height, 2)

    %Rect{
      x: parent.x,
      y: parent.y + y_offset,
      width: parent.width,
      height: height
    }
  end

  @doc """
  Builds the standard hint `%Paragraph{}` from a list of segments.

  Segments are tuples of `{text, kind}`:

    * `{text, :chip}` — reverse-video key chip (e.g. `" A "`).
    * `{text, :label}` — plain action label (e.g. `" pause"`).
  """
  @spec hint([hint_segment()]) :: Paragraph.t()
  def hint(segments) when is_list(segments) do
    spans =
      Enum.map(segments, fn
        {text, :chip} -> %Span{content: text, style: @chip_style}
        {text, :label} -> %Span{content: text}
      end)

    %Paragraph{text: spans}
  end

  @doc "The reverse-video `%Style{}` used for chip spans. Exposed for tests."
  @spec chip_style() :: Style.t()
  def chip_style(), do: @chip_style
end
