# ExRatatui screens on the badge

This folder is where the badge's [ex_ratatui](https://github.com/mauricio-cassola/ex_ratatui) demos live. Three of them rotate through the regular screen carousel alongside the Snake/Weather/Calendar screens, and a fourth one (the live BEAM dashboard) hangs off SSH as a subsystem so you can pull it up from your laptop without disturbing the e-ink panel.

The point of these screens is twofold. They're the demo for the library — the badge is a hostile rendering target (1-bit e-ink, 6×8 bitmap font, 350 ms partial-refresh budget), so anything that looks good on the badge is a fair test of ratatui-via-Rust talking to Elixir. They're also useful in their own right, especially the system monitor.

## What's in here

| Module | Type | What it shows |
| --- | --- | --- |
| `Counter` | reducer demo | Two-button counter, simplest possible end-to-end demo. Hits the chrome helper, the input mapping, and not much else. |
| `Goathi` | canvas + subscription demo | Animated 1-bit pixel-art goat with a tail-wagging animation, plus a "HI!" pixel-art word that blinks on/off in counter-rhythm with the wag. Both the goat and the greeting come from ASCII heredocs walked through `ascii_to_points/3` into a single `Canvas`. |
| `Stats` | data + widgets demo | Five-pane dashboard of live BEAM stats — header strip, memory-by-category bar chart, processes/atoms gauges, three rolling sparklines (memory, work-rate, run-queue), and a top-12 process panel. Refreshes every 3 s. |
| `NameBadge.SystemMonitorTui` | SSH subsystem | Three-tab full-color terminal dashboard registered as a `nerves_ssh` subsystem. Not in the on-device carousel — you reach it with `ssh -t -s`. Same library, much wider rendering surface (your laptop terminal). |

The first three are wrapped by thin menu-facing modules under `lib/name_badge/screen/` (`Counter`, `Goathi`, `Stats`) that hand the actual app off to the `NameBadge.Screen.ExRatatui` adapter. The adapter is what bridges the cell grid that ratatui produces to the e-ink panel's pixels — it traps exits, drains the initial frame, and feeds cells through `NameBadge.ExRatatui.Raster` to produce a 1-bit bitmap with the bitmap font in `NameBadge.ExRatatui.Font`.

## Adding a new screen

Two layers, then one line in the carousel.

**Write the ratatui app** under `lib/name_badge/screen/ex_ratatui/<your_screen>.ex`. This is plain ex_ratatui, no badge-specific knowledge — same shape as Counter/Goathi/Stats.

```elixir
defmodule NameBadge.Screen.ExRatatui.Hello do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Widgets.Paragraph
  alias NameBadge.ExRatatui.DemoFrame

  @impl true
  def init(_opts), do: {:ok, %{count: 0}}

  @impl true
  def render(state, frame) do
    {block, block_rect, content_rect, hint_rect} = DemoFrame.layout("hello", frame)
    text_rect = DemoFrame.center_row(content_rect, 1)

    [
      {block, block_rect},
      {%Paragraph{text: "hello world (#{state.count})", alignment: :center}, text_rect},
      {DemoFrame.hint([{" A ", :chip}, {" tick", :label}, {" B long ", :chip}, {" back", :label}]), hint_rect}
    ]
  end

  @impl true
  def update({:event, %Key{code: "up"}}, state), do: {:noreply, %{state | count: state.count + 1}}
  def update(_, state), do: {:noreply, state}
end
```

**Add the menu wrapper** at `lib/name_badge/screen/hello.ex`. This is a one-liner that lets the regular screen rotation host the ratatui app:

```elixir
defmodule NameBadge.Screen.Hello do
  use NameBadge.Screen.ExRatatui, app: NameBadge.Screen.ExRatatui.Hello
end
```

**Register in the carousel** by adding the wrapper to `@base_screens` in `lib/name_badge/screen/top_level.ex`:

```elixir
@base_screens [
  ...
  {Screen.Hello, "Hello"},
  ...
]
```

That's it. Build firmware, OTA over SSH, hold A to advance the carousel until you find your screen.

### Two things about writing ex_ratatui apps for the badge that are worth knowing up front

The badge font is a 6×8 bitmap with limited Unicode coverage. Plain ASCII works, box-drawing characters and the gauge blocks (`█ ▄ ▁ ▂ ▃ ▅ ▇`) work. Things that look ASCII-ish but aren't — the middle dot `·`, ellipsis `…`, smart quotes, em dashes, `|>` — render as a placeholder checker glyph. When in doubt, build firmware and look at the actual rendered output, the simulator's font has more glyphs than the badge does.

The e-ink panel is 1-bit. Color and styling get squashed at the raster layer in `NameBadge.ExRatatui.Raster`: only `:reversed` modifier or `bg: :black` produce inverted (paper-on-ink) cells; everything else paints as ink-on-paper. Setting `border_style: %Style{fg: :cyan}` or similar does nothing on the badge but might look fancy in the simulator and the SystemMonitorTui — that's fine, just don't rely on it for legibility.

## The shared chrome — `DemoFrame`

`NameBadge.ExRatatui.DemoFrame` (in `lib/name_badge/ex_ratatui/`) is the helper every demo uses for its outer block + bottom hint strip. The intent is that all three screens look like siblings: same title style, same hint row layout, same border. If you reach for it in your new screen, you get that for free.

The shape is:

```elixir
{block, block_rect, content_rect, hint_rect} = DemoFrame.layout("hello", frame)
```

`block` is the outer `%Block{}` titled ` ex_ratatui - hello `. `block_rect` covers everything except the bottom row. `content_rect` is the inside of the block (one cell in from each border). `hint_rect` is the bottom row, padded two cells in from each side.

There's also `DemoFrame.center_row(content_rect, height)` for vertically centering a content row, and `DemoFrame.hint(segments)` for building reverse-video key-chip + plain-label hint paragraphs. See Counter for the minimal example, Stats for a wallpaper-it-everywhere example.

## The SSH subsystem (`SystemMonitorTui`)

The full-color BEAM dashboard isn't in the carousel — it lives at `lib/name_badge/system_monitor_tui.ex` and gets registered as a `nerves_ssh` subsystem in `config/runtime.exs`:

```elixir
config :nerves_ssh,
  subsystems: [
    :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
    ExRatatui.SSH.subsystem(NameBadge.SystemMonitorTui)
  ]
```

From your laptop:

```sh
ssh -t nerves@wisteria.local -s Elixir.NameBadge.SystemMonitorTui
```

`-t` is mandatory. OpenSSH does not allocate a PTY for `-s` subsystem mode by default — without it your local terminal stays in cooked mode and keystrokes get line-buffered instead of flowing to the TUI. Plain `ssh nerves@wisteria.local` (no `-s`) still gives you the regular IEx prompt, and from IEx you can also kick the same TUI off with `NameBadge.SystemMonitorTui.run()`.

Three tabs, switched with `1` / `2` / `3`:

- **Overview** — host info, BEAM info, RAM and BEAM-heap line gauges, pool bar chart, scheduler bar chart.
- **Processes** — top 20 by memory, scrollable with `j` / `k`.
- **Graphs** — RAM %, load-average lines (1m/5m/15m), and a scheduler-utilization sparkline. 60 seconds of history.

`q` quits the subsystem and disconnects the SSH session. The badge's e-ink screen carousel keeps doing its thing the whole time.

### Adding another SSH subsystem

The pattern is the same — write an `ExRatatui.App` module anywhere under `lib/`, then add a line to the `subsystems:` list in `runtime.exs`:

```elixir
ExRatatui.SSH.subsystem(NameBadge.YourTui)
```

It has to be `runtime.exs`, not `target.exs`, because `ExRatatui.SSH.subsystem/1` is a function call and the `target.exs` config is evaluated before Mix has compiled target deps. `runtime.exs` runs at boot, after every beam file has loaded, before `:nerves_ssh` starts — so the function is safe to call there. The whole block is guarded by `if Application.spec(:nerves_ssh)` so the same config is harmless on host builds.

## How rendering reaches the panel

Useful to know if you ever need to debug a glyph that won't render or a layout that's off:

1. Your ex_ratatui app produces a list of `{widget, rect}` pairs in `render/2`.
2. ratatui (the Rust crate, via NIF) walks that list and paints into a cell grid.
3. `NameBadge.Screen.ExRatatui` adapter pulls the cell session, drains it, and hands cells to `NameBadge.ExRatatui.Raster`.
4. The raster looks up each cell's character in `NameBadge.ExRatatui.Font` (a packed 6×8 bitmap), applies inversion if the cell is reversed or `bg: :black`, and writes pixels into a 400×300 1-bit bitmap.
5. The bitmap goes to `NameBadge.Display`, which sends it to the UC8276 e-ink controller.

If something looks wrong on hardware but right in the simulator, the suspect is almost always step 4 (font glyph missing, or unintended inversion). The raster has a small set of unit tests covering inversion semantics — start there.
