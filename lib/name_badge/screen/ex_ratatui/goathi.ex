defmodule NameBadge.Screen.ExRatatui.Goathi do
  @moduledoc """
  Animated Goathi greeting — the canvas-and-subscriptions showcase
  for the `NameBadge.Screen.ExRatatui` adapter and the screen that
  says "hi!" from ex_ratatui at the conference.

  Renders a 1-bit pixel-art front-view goat face — outlined contour,
  two ears, and two eyes drawn as filled squares — and a "HI!"
  pixel-art word in the top-left of the canvas. Every other tick the
  greeting flashes on and the right eye blinks (drops to a single
  dash row), so the goat winks while it speaks. Each art heredoc is
  parsed once at compile time by `NameBadge.Screen.ExRatatui.Goathi.Art`
  into a `%Canvas.Points{}` and baked into a module attribute — render
  is then pure assembly of the pre-built shapes layered in order so
  the eye sits on top of the face outline.

  Built on the reducer runtime — one `update/2` clause per
  `{:event, …}` / `{:info, …}` shape — so it doubles as a tour of
  how to write a self-ticking ExRatatui app. Chrome (outer block +
  bottom hint strip) comes from `NameBadge.ExRatatui.Frame` so
  every demo uses the screen the same way.

  The 1 s tick is tuned for the badge's UC8276 partial-refresh
  budget (≈ 350 ms). On the simulator this looks slower than a
  desktop animation would; that's deliberate, the app should look
  the same place the firmware ends up running.

  ## Editing the goat

  The pixel-art lives in four module attributes — `@face_art`,
  `@right_eye_open`, `@right_eye_closed`, and `@hi_art`. They're
  plain heredoc strings: any non-space character is an ink pixel,
  ` ` is paper. The `@*_origin_*` constants control where each
  shape sits inside the canvas.

  ## Controls

  | Key (TUI) | Badge button     | Action                  |
  | --------- | ---------------- | ----------------------- |
  | `up`      | A (single press) | Pause/resume the blink  |
  | `home`    | A (long press)   | Reset to tick 0         |
  | —         | B (long press)   | Back to menu (handled by `NameBadge.Screen`) |
  """

  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Subscription
  alias ExRatatui.Widgets.Canvas
  alias NameBadge.ExRatatui.Frame
  alias NameBadge.Screen.ExRatatui.Goathi.Art

  @tick_interval_ms 1_000

  # Front-view goat face: short pointy ears, wide forehead, the head
  # sides going straight down through the eye row, then a hard taper
  # into a narrow snout at the bottom — front-view goats read as a
  # downward-pointing triangle, not a rounded blob. Contour is a
  # 1-cell outline; the always-open left eye is baked in here. The
  # right eye sits in negative space and gets layered in by a
  # separate shape so it can blink between ticks. Everything is
  # symmetric around the vertical centerline; if you tweak one side,
  # mirror it.
  @face_art """
           ##        ##
          ####      ####
          ####      ####
      ######################
      ######################
  ######                    ######
  #####                    #####
   ####   ###              ####
    ###   ###              ###
     ##                    ##
      ##                  ##
       ##   ##########   ##
        ##   ##    ##   ##
         ##   ##  ##   ##
          ##    ##    ##
           ##        ##
            ##      ##
             ##    ##
              ##  ##
               ####
                ##
  """

  # Right eye when open: 2×2 filled square. Sits above
  # @right_eye_y_open so the bottom row lines up with the left eye.
  @right_eye_open """
  ###
  ###
  """

  # Right eye when closed: a single 1×2 dash. Anchored to the bottom
  # row of where the open eye would be, so the wink reads as the lid
  # coming down rather than the eye sliding around.
  @right_eye_closed """
  ###
  """

  # 5×14 "HI!" word in the same pixel-art style as the face. Sits in
  # the top-left of the canvas where the face never reaches.
  @hi_art """
  ##  ##  ####  ##
  ##  ##   ##   ##
  ######   ##   ##
  ##  ##   ##
  ##  ##  ####  ##
  """

  # Face top-left in canvas units. The render uses 1:1 cell mapping
  # (1 canvas unit == 1 cell), so these are roughly cell coordinates
  # within the content area. Pushes the face into the right half of
  # the canvas so HI! fits on the left.
  @face_origin_x 30.0
  @face_origin_y 30.0

  # Right eye anchor. `*_open` is the y of the eye's TOP row,
  # `*_closed` is the y of the dash row (which equals the eye's
  # BOTTOM row). The face's left eye lives at art rows 7-8, which
  # canvas-coord-wise is y=23 (top) / y=22 (bottom) given face origin
  # y=30. The face's eye-row symmetry axis runs through canvas
  # x=45.5 (the row-7 cheek midpoint between canvas x=33-36 and
  # x=55-58). The left eye centers on canvas x=41, so the right eye
  # centers on x=50 — its 3 cells span canvas x=49..51. That keeps
  # the cheek-to-eye gap on both sides at 3 cells.
  @right_eye_x 49.0
  @right_eye_y_open 23.0
  @right_eye_y_closed 22.0

  # HI! word top-left. Far enough left of the face that they never
  # touch even at the longest art column.
  @hi_origin_x 2.0
  @hi_origin_y_top 32.0

  # The art is static and the origins are compile-time numbers, so the
  # resulting `%Points{}` is also static. Bake them once at compile
  # time instead of re-parsing the heredocs on every render.
  @face_points Art.ascii_to_points(@face_art, @face_origin_x, @face_origin_y)
  @hi_points Art.ascii_to_points(@hi_art, @hi_origin_x, @hi_origin_y_top)
  @right_eye_open_points Art.ascii_to_points(@right_eye_open, @right_eye_x, @right_eye_y_open)
  @right_eye_closed_points Art.ascii_to_points(
                             @right_eye_closed,
                             @right_eye_x,
                             @right_eye_y_closed
                           )

  @impl ExRatatui.App
  def init(_opts), do: {:ok, %{tick: 0, paused?: false}}

  @impl ExRatatui.App
  def render(state, frame) do
    {_block, block_rect, content_rect, hint_rect} = Frame.layout("goathi", frame)

    # Canvas takes its own `:block` (the borders + title sit on the
    # Canvas struct so the marker pixels paint inside them), so we
    # discard the standalone Frame block and paint the canvas
    # across the same `block_rect`. Bounds are sized 1:1 with the
    # inner content area — one canvas unit equals one cell, so pixel
    # art stays square.
    canvas = %Canvas{
      x_bounds: {0.0, content_rect.width * 1.0},
      y_bounds: {0.0, content_rect.height * 1.0},
      marker: :block,
      shapes: shapes(state),
      block: Frame.title_block("goathi")
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
    if hi_visible?(state.tick) do
      # Speaking + winking: HI! shows, right eye drops to a dash.
      [@hi_points, @right_eye_closed_points, @face_points]
    else
      # Resting: no HI!, right eye fully open.
      [@right_eye_open_points, @face_points]
    end
  end

  @doc """
  Whether the "HI!" word is shown on the canvas at the given tick,
  and (matching) whether the right eye is mid-blink. Public so tests
  can assert the alternation without going through the full
  `render/2` pipeline.

  Greeting + wink land on even ticks; the resting open-eye pose is
  on odd ticks. The two animations breathe together at half the
  tick rate each.
  """
  @spec hi_visible?(non_neg_integer()) :: boolean()
  def hi_visible?(tick) when is_integer(tick) and tick >= 0,
    do: rem(tick, 2) == 0

  defp hint_paragraph(state) do
    pause_label = if state.paused?, do: " resume   ", else: " pause    "

    Frame.hint([
      {" A ", :chip},
      {pause_label, :label},
      {" A long ", :chip},
      {" reset    ", :label},
      {" B long ", :chip},
      {" back", :label}
    ])
  end
end
