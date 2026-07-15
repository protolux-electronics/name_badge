defmodule NameBadge.Screen.Settings.Calibrate do
  @moduledoc """
  Two-step grayscale calibration wizard for the 4-level UC8276 panel.

  The panel shows exactly 4 levels: black and white are fixed anchors, the two
  middle grays are all you can move. With only two buttons (short A/B adjust,
  long A "next", long B "exit"), a single gray can be tuned per screen — so the
  two mids split across two steps:

      Step 1 — Dark gray   (tune the darker mid)
      Step 2 — Light gray  (tune the lighter mid)

  Both steps show the same full-screen photo, dithered to the 4 levels at
  runtime, so you judge each gray against a real image.

  Each step fills the whole 400x300 screen: a value label on top, a plain
  marker bar on the left (dark at top → light at bottom, a single notch at the
  current count — no gradient, so it reads as pure position, and scaled to the
  usable count range rather than the full 0..54), the maximized test image, and
  all four button hints on the bottom.

  Short A darkens / short B lightens the current step's gray, applied live via
  `NameBadge.Calibration` (~1s redraw). Long A advances; on step 2 it saves to
  `/data` and exits. Long B exits without saving (reverts on reboot).
  """

  use NameBadge.Screen

  alias NameBadge.Calibration

  # Height of the bar/image row (also the photo's square px size) and bar width.
  @row_h 236
  @bar_w 20
  # The response curve is steep — only the first ~15 counts are usable (higher
  # just saturates to white), so the marker bar scales to this, not to 54.
  @usable_max 16
  # Marker notch height, in pt.
  @marker_h 4

  # Full-tone test photo (Kodak "kodim17" from the Kodak Lossless True Color
  # Image Suite, https://r0k.us/graphics/kodak/).
  @test_photo "kodim17.png"

  @impl NameBadge.Screen
  def mount(_args, screen) do
    {dark, light} = Calibration.load()
    Calibration.set(dark, light)
    dither_photo()

    screen =
      screen
      |> assign(step: :dark, dark: dark, light: light)
      |> assign(button_hints: %{a: "Darker", b: "Lighter"})
      # Content is composed at exactly the 4 levels {0, 85, 170, 255} — flat
      # fills, and the photo error-diffused to those values (below) — so eink's
      # own dithering is off; each pixel maps 1:1 onto the calibrated levels.
      |> assign(render_opts: [mode: :grayscale, dither: false])

    {:ok, screen}
  end

  # Take the bundled full-tone photo and run it through the same pipeline the
  # grayscale screens use (grayscale → 2-bit error diffusion), so the preview
  # shows how a real image actually renders on the 4-level panel. Written once
  # per screen entry to a tmp file the Typst compose step embeds.
  defp dither_photo do
    Path.join(priv_images(), @test_photo)
    |> File.read!()
    |> Dither.decode!()
    |> Dither.resize!(@row_h, @row_h)
    |> Dither.grayscale!()
    |> Dither.dither!(algorithm: :stucki, bit_depth: 2)
    |> Dither.encode!()
    |> then(&File.write!(photo_path(), &1))
  end

  # ── Buttons ────────────────────────────────────────────────────────────────
  # Short A/B nudge the current gray; long A advances (save+exit on step 2).
  # Long B → back is handled globally by NameBadge.Screen.

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, screen), do: {:noreply, nudge(screen, -1)}
  def handle_button(:button_2, :single_press, screen), do: {:noreply, nudge(screen, +1)}

  def handle_button(:button_1, :long_press, %{assigns: %{step: :dark}} = screen) do
    {:noreply, assign(screen, step: :light)}
  end

  def handle_button(:button_1, :long_press, %{assigns: %{step: :light}} = screen) do
    Calibration.save(screen.assigns.dark, screen.assigns.light)
    {:noreply, navigate(screen, :back)}
  end

  def handle_button(_button, _press, screen), do: {:noreply, screen}

  # Adjust the current step's gray by `delta` counts, re-apply live, clamp.
  defp nudge(%{assigns: %{step: :dark, dark: d, light: l}} = screen, delta) do
    {d, l} = Calibration.set(d + delta, l)
    assign(screen, dark: d, light: l)
  end

  defp nudge(%{assigns: %{step: :light, dark: d, light: l}} = screen, delta) do
    {d, l} = Calibration.set(d, l + delta)
    assign(screen, dark: d, light: l)
  end

  # ── Render ───────────────────────────────────────────────────────────────
  # Full-bleed 400x300 composition (returns a PNG, bypassing the bordered
  # settings layout) so the test image gets the whole screen. Layout:
  #   label ────────────────────
  #   [bar] │  big test image
  #   hold A · A · B · hold B

  # The dithered photo, filling the large right-hand cell (both steps).
  @photo ~s|align(center + horizon, image("photo.png", height: 100%, fit: "contain"))|

  @impl NameBadge.Screen
  def render(%{step: :dark} = assigns) do
    {default, _} = Calibration.defaults()
    compose("Dark gray", assigns.dark, default, "next")
  end

  def render(%{step: :light} = assigns) do
    {_, default} = Calibration.defaults()
    compose("Light gray", assigns.light, default, "save")
  end

  # Build the full-page grayscale composition and render it to a PNG. Rendered
  # from the tmp root so it can embed the runtime-dithered photo.
  defp compose(label, value, default, long_a) do
    # Plain track (dark at top, light at bottom), with a single marker notch at
    # the current count — no gradient, so the bar reads as pure position.
    frac = min(value, @usable_max) / @usable_max
    marker_dy = Float.round(frac * (@row_h - @marker_h), 1)

    template = """
    #set page(width: 400pt, height: 300pt, margin: (x: 14pt, top: 10pt, bottom: 8pt))
    #set text(font: "Poppins", size: 14pt)

    #stack(dir: ttb, spacing: 8pt,
      text(size: 16pt)[#{label}: #text(weight: "bold")[#{value}] #h(8pt) #text(size: 12pt, fill: rgb(85, 85, 85))[(default=#{default})]],
      grid(columns: (#{@bar_w}pt, 1fr), column-gutter: 12pt, rows: (#{@row_h}pt,),
        box(width: #{@bar_w}pt, height: #{@row_h}pt)[
          #rect(width: 100%, height: 100%, stroke: 1pt + black)
          #place(top + left, dy: #{marker_dy}pt, rect(width: 100%, height: #{@marker_h}pt, fill: black))
        ],
        #{@photo}
      ),
      align(center, text(size: 11pt, fill: rgb(85, 85, 85))[hold A: #{long_a}   ·   A darker   ·   B lighter   ·   hold B: exit])
    )
    """

    Typst.render_to_png!(template, [], root_dir: tmp_root(), extra_fonts: [fonts_dir()])
    |> List.first()
  end

  # ── Paths ────────────────────────────────────────────────────────────────

  defp priv_images, do: Application.app_dir(:name_badge, "priv/typst/images")
  defp fonts_dir, do: Application.app_dir(:name_badge, "priv/typst/fonts")
  defp photo_path, do: Path.join(tmp_root(), "photo.png")

  defp tmp_root do
    dir = Path.join(System.tmp_dir!(), "name_badge_calibrate")
    File.mkdir_p!(dir)
    dir
  end
end
