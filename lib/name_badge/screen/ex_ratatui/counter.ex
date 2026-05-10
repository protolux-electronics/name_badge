defmodule NameBadge.Screen.ExRatatui.Counter do
  @moduledoc """
  A two-button TUI counter — the first end-to-end demo of the
  `NameBadge.Screen.ExRatatui` adapter and the showcase that exercises
  the rasterer's reverse-video support along with the font's
  lowercase + box-drawing coverage.

  ## Layout

      ┌─ counter ────────────────────────────────┐
      │                                          │
      │              count: 42                   │
      │                                          │
      └──────────────────────────────────────────┘

       [ A ]  +1   [ A long ]  reset
       [ B ]  -1   [ B long ]  back

  The bracketed key labels render in reverse-video — paper glyphs on
  an ink background — so the user can see at a glance which inputs
  the screen responds to. The Block border, title, and lowercase
  text all exercise font + raster paths the original Counter didn't.

  ## Controls

  | Key (TUI) | Badge button     | Action       |
  | --------- | ---------------- | ------------ |
  | `up`      | A (single press) | Increment    |
  | `down`    | B (single press) | Decrement    |
  | `home`    | A (long press)   | Reset to 0   |
  | —         | B (long press)   | Back to menu (handled by `NameBadge.Screen`) |

  The mapping from badge button to TUI key code is owned by
  `NameBadge.Screen.ExRatatui`'s default key map; this app only cares
  about the `code` strings.
  """

  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Paragraph}

  @reversed %Style{modifiers: [:reversed]}

  @impl ExRatatui.App
  def mount(_opts), do: {:ok, %{count: 0}}

  @impl ExRatatui.App
  def render(state, frame) do
    block_rect = %Rect{x: 2, y: 1, width: frame.width - 4, height: 9}

    count_rect = %Rect{
      x: block_rect.x + 1,
      y: block_rect.y + div(block_rect.height, 2),
      width: block_rect.width - 2,
      height: 1
    }

    hint_y = block_rect.y + block_rect.height + 2

    [
      {%Block{title: " ex_ratatui · counter ", borders: [:all]}, block_rect},
      {%Paragraph{text: "count: #{state.count}", alignment: :center}, count_rect},
      {hint_paragraph([
         {" A ", :reversed},
         {"  +1    ", :plain},
         {" A long ", :reversed},
         {"  reset", :plain}
       ]), %Rect{x: 4, y: hint_y, width: frame.width - 8, height: 1}},
      {hint_paragraph([
         {" B ", :reversed},
         {"  -1    ", :plain},
         {" B long ", :reversed},
         {"  back", :plain}
       ]), %Rect{x: 4, y: hint_y + 1, width: frame.width - 8, height: 1}}
    ]
  end

  @impl ExRatatui.App
  def handle_event(%Key{code: "up"}, state), do: {:noreply, %{state | count: state.count + 1}}
  def handle_event(%Key{code: "down"}, state), do: {:noreply, %{state | count: state.count - 1}}
  def handle_event(%Key{code: "home"}, state), do: {:noreply, %{state | count: 0}}
  def handle_event(_event, state), do: {:noreply, state}

  @impl ExRatatui.App
  def handle_info(_message, state), do: {:noreply, state}

  defp hint_paragraph(segments) do
    spans =
      Enum.map(segments, fn
        {text, :reversed} -> %Span{content: text, style: @reversed}
        {text, :plain} -> %Span{content: text}
      end)

    %Paragraph{text: spans}
  end
end
