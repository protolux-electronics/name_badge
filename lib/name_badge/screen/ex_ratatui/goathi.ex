defmodule NameBadge.Screen.ExRatatui.Goathi do
  @moduledoc """
  Animated Goathi greeting — the canvas-and-subscriptions showcase
  for the `NameBadge.Screen.ExRatatui` adapter and the screen that
  says "hi!" from ex_ratatui at the conference.

  Renders a 1-bit pixel-art goat by walking two ASCII-art frames
  through `ascii_to_points/3` (each `#`/non-space character becomes a
  block-marker cell on the canvas) and swapping between them on a 1 s
  tick declared via `ExRatatui.Subscription.interval/3`. A "HI!"
  pixel-art word blinks on/off in counter-rhythm with the wagging
  tail — when the tail is down the goat "speaks", when it lifts the
  tail the word disappears. Built on the reducer runtime — one
  `update/2` clause per `{:event, …}` / `{:info, …}` shape — so it
  doubles as a tour of how to write a self-ticking ExRatatui app.
  Chrome (outer block + bottom hint strip) comes from
  `NameBadge.ExRatatui.DemoFrame` so every demo uses the screen the
  same way.

  The 1 s tick is tuned for the badge's UC8276 partial-refresh
  budget (≈ 350 ms). On the simulator this looks slower than a
  desktop animation would; that's deliberate, the app should look
  the same place the firmware ends up running.

  ## Editing the goat

  The pixel-art lives in three module attributes — `@frame_tail_down`,
  `@frame_tail_up`, and `@hi_art`. They're plain heredoc strings:
  any non-space character is an ink pixel, ` ` is paper. To restyle
  the goat or the greeting, edit those strings; the frames don't
  need to be the same width or height. The `@goat_origin_*` and
  `@hi_origin_*` constants control where each shape sits inside the
  canvas.

  ## Controls

  | Key (TUI) | Badge button     | Action               |
  | --------- | ---------------- | -------------------- |
  | `up`      | A (single press) | Pause/resume the wag |
  | `home`    | A (long press)   | Reset the tail to rest |
  | —         | B (long press)   | Back to menu (handled by `NameBadge.Screen`) |
  """

  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Subscription
  alias ExRatatui.Widgets.Canvas
  alias ExRatatui.Widgets.Canvas.Points
  alias NameBadge.ExRatatui.DemoFrame

  @tick_interval_ms 1_000

  # Pixel-art goat in profile, head + horns on the right, body
  # running horizontally across, four legs hanging down, tail next
  # to the body on the left so they read as one silhouette. Two
  # frames differ only in the tail position. Replace these heredocs
  # with refined art any time — the renderer will pick up whatever
  # shape they end up.
  @frame_tail_down """
                                          ###
                                        ## ##
                                       ##   ##
                                      ##    ##
                                      ##   ##
                                       ## ##
                                        ###
                                       #####
                                      ##oo##
                                     ########
   ###                          #############
  ####                       ################
   ###                     ###################
                          #####################
                         #######################
                         #######################
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                          #    #    #    #
  """

  @frame_tail_up """
                                          ###
   ###                                  ## ##
  ####                                 ##   ##
   ###                                ##    ##
                                      ##   ##
                                       ## ##
                                        ###
                                       #####
                                      ##oo##
                                     ########
                                #############
                              ################
                            ###################
                          #####################
                         #######################
                         #######################
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                         ##  ##   ##   ##   ##
                          #    #    #    #
  """

  @frames [@frame_tail_down, @frame_tail_up]

  # 5×14 "HI!" word in the same pixel-art style as the goat. Sits in
  # the top-left of the canvas where both wag frames are empty, so it
  # never overlaps the silhouette. Toggled on/off in counter-rhythm
  # with the tail wag.
  @hi_art """
  ##  ##  ###  ##
  ##  ##   #   ##
  ######   #   ##
  ##  ##   #
  ##  ##  ###  ##
  """

  # Goat top-left in canvas units. The render uses 1:1 cell mapping
  # (1 canvas unit == 1 cell), so these are roughly cell coordinates
  # within the content area. Tuned so the silhouette sits roughly
  # centered with the head poking up on the right.
  @goat_origin_x 0.0
  @goat_origin_y_top 30.0

  # HI! word top-left in canvas units. Sits above the (empty) tail
  # area at the top-left of the canvas; high enough to clear the
  # tail-up frame's lifted tail.
  @hi_origin_x 2.0
  @hi_origin_y_top 32.0

  @impl ExRatatui.App
  def init(_opts), do: {:ok, %{tick: 0, paused?: false}}

  @impl ExRatatui.App
  def render(state, frame) do
    {_block, block_rect, content_rect, hint_rect} = DemoFrame.layout("goathi", frame)

    # Canvas takes its own `:block` (the borders + title sit on the
    # Canvas struct so the marker pixels paint inside them), so we
    # discard the standalone DemoFrame block and paint the canvas
    # across the same `block_rect`. Bounds are sized 1:1 with the
    # inner content area — one canvas unit equals one cell, so pixel
    # art stays square.
    canvas = %Canvas{
      x_bounds: {0.0, content_rect.width * 1.0},
      y_bounds: {0.0, content_rect.height * 1.0},
      marker: :block,
      shapes: shapes(state),
      block: DemoFrame.title_block("goathi")
    }

    [
      {canvas, block_rect},
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

  defp shapes(state) do
    art = Enum.at(@frames, rem(state.tick, length(@frames)))
    goat = ascii_to_points(art, @goat_origin_x, @goat_origin_y_top)

    if hi_visible?(state.tick) do
      [ascii_to_points(@hi_art, @hi_origin_x, @hi_origin_y_top), goat]
    else
      [goat]
    end
  end

  @doc """
  Whether the "HI!" word is shown on the canvas at the given tick.
  Public so tests can assert the alternation without going through
  the full `render/2` pipeline.

  HI! shows on even ticks (when the tail is down) and disappears on
  odd ticks (when the tail is up), so the two animations breathe
  together at half the tick rate each.
  """
  @spec hi_visible?(non_neg_integer()) :: boolean()
  def hi_visible?(tick) when is_integer(tick) and tick >= 0,
    do: rem(tick, 2) == 0

  @doc """
  Walks an ASCII-art string and emits a single
  `%ExRatatui.Widgets.Canvas.Points{}` carrying one coordinate per
  non-space character. Row 0 of the art lines up with `y_origin`;
  each subsequent row sits one canvas-unit below. Designed to be
  fed straight into a `:block`-marker `Canvas` whose bounds are
  sized 1:1 with cells.

  Public so tests and refinement scripts can call it without
  reaching into the module's private API.
  """
  @spec ascii_to_points(String.t(), number(), number()) :: Points.t()
  def ascii_to_points(art, x_origin, y_origin) when is_binary(art) do
    coords =
      art
      |> String.split("\n")
      |> Enum.with_index()
      |> Enum.flat_map(fn {row_str, row} ->
        row_str
        |> String.graphemes()
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {" ", _col} -> []
          {_char, col} -> [{x_origin + col * 1.0, y_origin - row * 1.0}]
        end)
      end)

    %Points{coords: coords, color: :white}
  end

  defp hint_paragraph(state) do
    pause_label = if state.paused?, do: " resume   ", else: " pause    "

    DemoFrame.hint([
      {" A ", :chip},
      {pause_label, :label},
      {" A long ", :chip},
      {" reset    ", :label},
      {" B long ", :chip},
      {" back", :label}
    ])
  end
end
