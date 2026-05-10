defmodule NameBadge.Screen.ExRatatui.Goatmire do
  @moduledoc """
  Animated Goatmire-themed greeting card — the canvas-and-subscriptions
  showcase for the `NameBadge.Screen.ExRatatui` adapter.

  Draws a chunky 1-bit goat on a `Canvas` with the `:block` marker so
  it works on the e-ink font (which has no braille glyphs), then wags
  the tail on a 1 s tick declared via
  `ExRatatui.Subscription.interval/3`. Built on the reducer runtime —
  one `update/2` clause per `{:event, …}` / `{:info, …}` shape — so it
  doubles as a tour of how to write a self-ticking ExRatatui app.

  The 1 s tick is tuned for the badge's UC8276 partial-refresh budget
  (≈ 350 ms per refresh). On the simulator this looks slower than a
  desktop animation would; that's deliberate, the app should look the
  same place the firmware ends up running.

  ## Layout

      ┌─ hi from ex_ratatui ─────────────────────────┐
      │                                              │
      │           ╓─ goat goes here ─╖               │
      │                                              │
      └──────────────────────────────────────────────┘

       [ A ] pause   [ A long ] reset   [ B long ] back

  ## Controls

  | Key (TUI) | Badge button     | Action               |
  | --------- | ---------------- | -------------------- |
  | `up`      | A (single press) | Pause/resume the wag |
  | `home`    | A (long press)   | Reset the tail to rest |
  | —         | B (long press)   | Back to menu (handled by `NameBadge.Screen`) |
  """

  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Block, Canvas, Paragraph}
  alias ExRatatui.Widgets.Canvas.{Line, Points, Rectangle}

  @reversed %Style{modifiers: [:reversed]}

  # Tail swing parameters: ~33° amplitude around 135° (up-left). With
  # the 1 s tick and a 0.5 rad/tick advance, each full wag cycle takes
  # ~12.5 s — slow enough for the e-ink partial refresh to keep up,
  # fast enough that the user sees the tail move every second.
  @tail_step 0.5
  @tail_amplitude :math.pi() / 5.5
  @tail_baseline :math.pi() * 3 / 4
  @tail_length 6.0
  @tick_interval_ms 1_000

  @impl ExRatatui.App
  def init(_opts), do: {:ok, %{tick: 0, paused?: false}}

  @impl ExRatatui.App
  def render(state, frame) do
    canvas_rect = %Rect{x: 0, y: 0, width: frame.width, height: frame.height - 2}
    hint_rect = %Rect{x: 2, y: frame.height - 1, width: frame.width - 4, height: 1}

    canvas = %Canvas{
      x_bounds: {-30.0, 30.0},
      y_bounds: {-10.0, 14.0},
      marker: :block,
      shapes: goat_shapes(state),
      block: %Block{title: " ex_ratatui · goatmire ", borders: [:all]}
    }

    [
      {canvas, canvas_rect},
      {hint_paragraph(state), hint_rect}
    ]
  end

  @impl ExRatatui.App
  def update({:event, %Key{code: "up"}}, state),
    do: {:noreply, %{state | paused?: not state.paused?}}

  def update({:event, %Key{code: "home"}}, state),
    do: {:noreply, %{state | tick: 0}}

  def update({:info, :tick}, %{paused?: true} = state),
    do: {:noreply, state}

  def update({:info, :tick}, state),
    do: {:noreply, %{state | tick: state.tick + 1}}

  def update(_msg, state), do: {:noreply, state}

  @impl ExRatatui.App
  def subscriptions(_state) do
    [Subscription.interval(:goat_tick, @tick_interval_ms, :tick)]
  end

  # Goat geometry, in canvas units. Head on the right, tail on the
  # left, only the tail moves. Coordinates are mathematical (Y grows
  # up), bottom-left anchoring on rectangles per the Canvas widget.
  defp goat_shapes(state) do
    body = %Rectangle{x: -12.0, y: -2.0, width: 14.0, height: 8.0, color: :white}
    head = %Rectangle{x: 2.0, y: 2.0, width: 8.0, height: 7.0, color: :white}

    horns = [
      %Line{x1: 2.0, y1: 9.0, x2: 0.0, y2: 13.0, color: :white},
      %Line{x1: 10.0, y1: 9.0, x2: 12.0, y2: 13.0, color: :white}
    ]

    eye = %Points{coords: [{8.0, 6.0}], color: :white}
    beard = %Line{x1: 4.0, y1: 2.0, x2: 4.0, y2: -1.0, color: :white}

    legs =
      for x <- [-10.0, -8.0, 0.0, -2.0] do
        %Line{x1: x, y1: -2.0, x2: x, y2: -7.0, color: :white}
      end

    [body, head, eye, beard, tail_shape(state) | horns ++ legs]
  end

  defp tail_shape(state) do
    angle = @tail_baseline + @tail_amplitude * :math.sin(state.tick * @tail_step)
    {bx, by} = {-12.0, 5.0}
    tx = bx + @tail_length * :math.cos(angle)
    ty = by + @tail_length * :math.sin(angle)
    %Line{x1: bx, y1: by, x2: tx, y2: ty, color: :white}
  end

  defp hint_paragraph(state) do
    pause_label = if state.paused?, do: "  resume   ", else: "  pause    "

    spans = [
      %Span{content: " A ", style: @reversed},
      %Span{content: pause_label},
      %Span{content: " A long ", style: @reversed},
      %Span{content: "  reset    "},
      %Span{content: " B long ", style: @reversed},
      %Span{content: "  back"}
    ]

    %Paragraph{text: spans}
  end
end
