# ExRatatui screens on the badge

This folder is where the badge's [ex_ratatui](https://github.com/mauricio-cassola/ex_ratatui) demos live. Three of them rotate through the regular screen carousel alongside the Snake/Weather/Calendar screens, and a fourth one (the live BEAM dashboard) hangs off SSH as a subsystem so you can pull it up from your laptop and monitor the badge.

## What's in here

| Module | Type | What it shows |
| --- | --- | --- |
| `Counter` | reducer demo | Two-button counter, simplest possible end-to-end demo. Hits the chrome helper, the input mapping, and not much else. |
| `Goathi` | canvas + subscription demo | Animated 1-bit pixel-art goat with a tail-wagging animation, plus a "HI!" pixel-art word that blinks on/off in counter-rhythm with the wag. Both the goat and the greeting come from ASCII heredocs walked through `ascii_to_points/3` into a single `Canvas`. |
| `Stats` | data + widgets demo | Five-pane dashboard of live BEAM stats — header strip, memory-by-category bar chart, processes/atoms gauges, three rolling sparklines (memory, work-rate, run-queue), and a top-12 process panel. Refreshes every 3 s. |
| `NameBadge.ExRatatui.SystemMonitorTui` | SSH subsystem | Three-tab full-color terminal dashboard registered as a `nerves_ssh` subsystem. Not in the on-device carousel — you reach it with `ssh -t -s`. Same library, much wider rendering surface. |

The first three are wrapped by thin menu-facing modules under `lib/name_badge/screen/` (`Counter`, `Goathi`, `Stats`) that hand the actual app off to the `NameBadge.Screen.ExRatatui` adapter. The adapter is what bridges the cell grid that ex_ratatui produces to the e-ink panel's pixels — it traps exits, drains the initial frame, and feeds cells through `NameBadge.ExRatatui.Raster` to produce a 1-bit bitmap with the bitmap font in `NameBadge.ExRatatui.Font`.

## Adding a new screen

Two layers, then one line in the carousel.

**Write the ex_ratatui app** under `lib/name_badge/screen/ex_ratatui/<your_screen>.ex`. This is plain ex_ratatui, no badge-specific knowledge. Same shape as Counter/Goathi/Stats.

```elixir
defmodule NameBadge.Screen.ExRatatui.Hello do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Widgets.Paragraph
  alias NameBadge.ExRatatui.Frame

  @impl true
  def init(_opts), do: {:ok, %{count: 0}}

  @impl true
  def render(state, frame) do
    {block, block_rect, content_rect, hint_rect} = Frame.layout("hello", frame)
    text_rect = Frame.center_row(content_rect, 1)

    [
      {block, block_rect},
      {%Paragraph{text: "hello world (#{state.count})", alignment: :center}, text_rect},
      {Frame.hint([{" A ", :chip}, {" tick", :label}, {" B long ", :chip}, {" back", :label}]), hint_rect}
    ]
  end

  @impl true
  def update({:event, %Key{code: "up"}}, state), do: {:noreply, %{state | count: state.count + 1}}
  def update(_, state), do: {:noreply, state}
end
```

**Add the menu wrapper** at `lib/name_badge/screen/hello.ex`. This is a one-liner that lets the regular screen rotation host the ex_ratatui app:

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
:
That's it.

### Two things about writing ex_ratatui apps for the badge that are worth knowing up front

The badge font is a 6×8 bitmap with limited Unicode coverage. Plain ASCII works, box-drawing characters and the gauge blocks (`█ ▄ ▁ ▂ ▃ ▅ ▇`) work. But other things I tried that look ASCII-ish but aren't — the middle dot `·`, ellipsis `…`, smart quotes, em dashes, `|>` — render as a placeholder checker glyph.

The e-ink panel is 1-bit. Color and styling get squashed at the raster layer in `NameBadge.ExRatatui.Raster`: only `:reversed` modifier or `bg: :black` produce inverted (paper-on-ink) cells; everything else paints as ink-on-paper. Setting `border_style: %Style{fg: :cyan}` or similar does nothing on the badge.

## The shared chrome — `Frame`

`NameBadge.ExRatatui.Frame` (in `lib/name_badge/ex_ratatui/`) is the helper every demo uses for its outer block + bottom hint strip. The intent is that all three screens look like siblings: same title style, same hint row layout, same border. If you reach for it in your new screen, you get that for free.

The shape is:

```elixir
{block, block_rect, content_rect, hint_rect} = Frame.layout("hello", frame)
```

`block` is the outer `%Block{}` titled ` ex_ratatui - hello `. `block_rect` covers everything except the bottom row. `content_rect` is the inside of the block (one cell in from each border). `hint_rect` is the bottom row, padded two cells in from each side.

There's also `Frame.center_row(content_rect, height)` for vertically centering a content row, and `Frame.hint(segments)` for building reverse-video key-chip + plain-label hint paragraphs. See Counter for the minimal example, Stats for a wallpaper-it-everywhere example.

This also acts as a demo of how one could "componentize" the TUIs. More on that: https://hexdocs.pm/ex_ratatui/custom_widgets.html

## The SSH subsystem (`SystemMonitorTui`)

The full-color BEAM dashboard isn't in the carousel — it lives at `lib/name_badge/ex_ratatui/system_monitor_tui.ex` and gets registered as a `nerves_ssh` subsystem in `config/runtime.exs`:

```elixir
config :nerves_ssh,
  subsystems: [
    :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
    ExRatatui.SSH.subsystem(NameBadge.ExRatatui.SystemMonitorTui)
  ]
```

To connect:

```sh
ssh -t nerves@wisteria.local -s Elixir.NameBadge.ExRatatui.SystemMonitorTui
```

`-t` is mandatory. OpenSSH does not allocate a PTY for `-s` subsystem mode by default — without it your local terminal stays in cooked mode and keystrokes get line-buffered instead of flowing to the TUI. Plain `ssh nerves@wisteria.local` (no `-s`) still gives you the regular IEx prompt, and from IEx you could also kick the same TUI off with `NameBadge.ExRatatui.SystemMonitorTui.run()` if the device has somewhere to render.

Three tabs, switched with `1` / `2` / `3`:

- **Overview** — host info, BEAM info, RAM and BEAM-heap line gauges, pool bar chart, scheduler bar chart.
- **Processes** — top 20 by memory, scrollable with `j` / `k`.
- **Graphs** — RAM %, load-average lines (1m/5m/15m), and a scheduler-utilization sparkline. 60 seconds of history.

`q` quits the subsystem and disconnects the SSH session. The badge's e-ink screen carousel keeps doing its thing the whole time.

### Adding another SSH subsystem

The pattern is the same — write an `ExRatatui.App` module anywhere under `lib/`, then add a line to the `subsystems:` list in `runtime.exs`:

```elixir
ExRatatui.SSH.subsystem(NameBadge.ExRatatui.YourTui)
```

And then:

```sh
ssh -t nerves@wisteria.local -s Elixir.NameBadge.ExRatatui.YourTui
```
