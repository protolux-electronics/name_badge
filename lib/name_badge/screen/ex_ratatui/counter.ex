defmodule NameBadge.Screen.ExRatatui.Counter do
  @moduledoc """
  A two-button TUI counter — the first end-to-end demo of the
  `NameBadge.Screen.ExRatatui` adapter.

  ## Controls

  | Key (TUI)            | Badge button       | Action       |
  | -------------------- | ------------------ | ------------ |
  | `up`                 | A (single press)   | Increment    |
  | `down`               | B (single press)   | Decrement    |
  | `home`               | A (long press)     | Reset to 0   |
  | (handled by `Screen`)| B (long press)     | Back to menu |

  The mapping from badge button to TUI key code is owned by
  `NameBadge.Screen.ExRatatui`'s default key map. Switching this app
  to e.g. left/right is a matter of passing a different `:key_map` in
  the screen's mount args, not editing this module.
  """

  @behaviour ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @impl ExRatatui.App
  def mount(_opts), do: {:ok, %{count: 0}}

  @impl ExRatatui.App
  def render(state, frame) do
    [
      {%Paragraph{text: "COUNTER", alignment: :center},
       %Rect{x: 0, y: 1, width: frame.width, height: 1}},
      {%Paragraph{text: "COUNT: #{state.count}", alignment: :center},
       %Rect{x: 0, y: div(frame.height, 2), width: frame.width, height: 1}},
      {%Paragraph{text: "A: +1    A LONG: RESET", alignment: :center},
       %Rect{x: 0, y: frame.height - 3, width: frame.width, height: 1}},
      {%Paragraph{text: "B: -1    B LONG: BACK", alignment: :center},
       %Rect{x: 0, y: frame.height - 2, width: frame.width, height: 1}}
    ]
  end

  @impl ExRatatui.App
  def handle_event(%Key{code: "up"}, state), do: {:noreply, %{state | count: state.count + 1}}
  def handle_event(%Key{code: "down"}, state), do: {:noreply, %{state | count: state.count - 1}}
  def handle_event(%Key{code: "home"}, state), do: {:noreply, %{state | count: 0}}
  def handle_event(_event, state), do: {:noreply, state}

  @impl ExRatatui.App
  def handle_info(_message, state), do: {:noreply, state}
end
