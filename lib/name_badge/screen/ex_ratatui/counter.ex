defmodule NameBadge.Screen.ExRatatui.Counter do
  @moduledoc """
  A two-button TUI counter — the simplest end-to-end demo of the
  `NameBadge.Screen.ExRatatui` adapter, sharing chrome with every
  other ExRatatui demo through `NameBadge.ExRatatui.DemoFrame`.

  ## Layout

      ┌─ ex_ratatui · counter ───────────────────────┐
      │                                              │
      │                                              │
      │                 count: 42                    │
      │                                              │
      │                                              │
      └──────────────────────────────────────────────┘

       [ A ] +1    [ A long ] reset    [ B ] -1    [ B long ] back

  ## Controls

  | Key (TUI) | Badge button     | Action       |
  | --------- | ---------------- | ------------ |
  | `up`      | A (single press) | Increment    |
  | `down`    | B (single press) | Decrement    |
  | `home`    | A (long press)   | Reset to 0   |
  | —         | B (long press)   | Back to menu (handled by `NameBadge.Screen`) |
  """

  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Widgets.Paragraph
  alias NameBadge.ExRatatui.DemoFrame

  @impl ExRatatui.App
  def mount(_opts), do: {:ok, %{count: 0}}

  @impl ExRatatui.App
  def render(state, frame) do
    {block, block_rect, content_rect, hint_rect} = DemoFrame.layout("counter", frame)
    count_rect = DemoFrame.center_row(content_rect, 1)

    [
      {block, block_rect},
      {%Paragraph{text: "count: #{state.count}", alignment: :center}, count_rect},
      {DemoFrame.hint([
         {" A ", :chip},
         {" +1    ", :label},
         {" A long ", :chip},
         {" reset    ", :label},
         {" B ", :chip},
         {" -1    ", :label},
         {" B long ", :chip},
         {" back", :label}
       ]), hint_rect}
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
