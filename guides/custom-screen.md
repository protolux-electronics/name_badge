# Custom Screens

Screens are implemented using a LiveView-like API. To get started creating a
custom screen, create a new file in `lib/name_badge/screen/custom_screen.ex`
with the following:

```elixir
defmodule NameBadge.Screen.CustomScreen do
  use NameBadge.Screen
end
```

Then, add your screen to the top level navigation in
`lib/name_badge/screen/top_level.ex`:

```diff
defmodule NameBadge.Screen.TopLevel do
  use NameBadge.Screen

  # ...

  @screens [
    {Screen.NameBadge, "Name Badge"},
    {Screen.Gallery, "Gallery"},
-   {Screen.Settings, "Device Settings"}
+   {Screen.Settings, "Device Settings"},
+   {Screen.CustomScreen, "Custom Screen"}
  ]

  # ...

end
```

Run `mix do firmware, upload wisteria.local` to put the new screen on your
device.

## Callbacks

You can render different content by implementing the various callbacks of the
`NameBadge.Screen` module. Those include:

- `render/1`
- `mount/2`
- `handle_button/3`
- `handle_info/2`
- `terminate/1`

## Render with Typst

The rendering pipeline of the name badge uses the Typst templating language. You
can read the documentation of Typst [here](https://typst.app/docs/). There is a
very user-friendly playground where you can get live preview of your screen
[here](https://typst.app/play/)

When rendered, several layout and formatting helpers are added to the beginning
of the template:

```typst
#set page(width: #{width}pt, height: #{height}pt, margin: #{margin}pt);
#set text(font: "Poppins", size: 20pt, weight: 500)

// rest of your content goes here
```

If you want to add extra fonts, images, or other assets, add them in the
appropriate directory in `priv/typst`.

An example of the `render/1` function for our custom screen could be as follows:

```elixir
def render(assigns) do
"""
#place(center + horizon, text(size: 32pt)[Hello World])
"""
end
```

## Assigns

Like LiveView, you can assign variables which are change-tracked. Screens only
re-render when some assigns have changed. You can assign them using the
`assign/2` or `assign/3` functions, which is already imported when invoking the
`use NameBadge.Screen` macro.

Assigns are passed to the `render/1` function. Unfortunately, we don't have
fancy sigils for Typst yet, so we just do string interpolation in the template.

Here is a simple example:

```elixir
defmodule NameBadge.Screen.CustomScreen do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(assigns) do
  """
  #place(center + horizon, text(size: 32pt)[Hello, #{assigns.name}])
  """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    # Passing arguments is currently unsupported, so the first parameter of
    # `mount/2` will always be `nil`. This will be implemented in a future release!
    {:ok, assign(screen, name: "John Doe")}
  end
end
```

## Handling Events

You can also implement the `handle_button/3` and `handle_info/2` callbacks to
react to button presses and messages.

For `handle_button/3`, the arguments are the button ID (either `:button_1` or
`:button_2`, which correspond to the labels "A" and "B" respectively), the press
type (either `:single_press` or `:long_press`), and the screen.

Do note that `handle_event(:button_2, :long_press, screen)` will never be
called - long press for this button invokes the `:back` navigation action.

Here's a simple example of a counter that resets every 5 seconds:

```elixir
defmodule NameBadge.Screen.CustomScreen do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(assigns) do
  """
  #place(center + horizon, text(size: 32pt)[You pressed #{assigns.count} times])
  """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    schedule_tick()
    {:ok, assign(screen, count: 0)}
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, screen) do
    new_count = screen.assigns.count + 1
    {:noreply, assign(screen, count: new_count)}
  end

  def handle_button(:button_2, :single_press, screen) do
    new_count = screen.assigns.count - 1
    {:noreply, assign(screen, count: new_count)}
  end

  # ignore button presses which don't match
  def handle_button(_button, _press, screen), do: {:noreply, screen}

  @impl NameBadge.Screen
  def handle_info(:tick, screen) do
    schedule_tick()
    {:noreply, assign(screen, count: 0)}
  end

  defp schedule_tick(), do: Process.send_after(self(), :tick, 5_000)
end
```

## Special Assigns

You can give users a hint of what each button press will do by assigning the
special assign, `:button_hints`. It requires a map where the keys are either
`:a`, `:b`, or `:ab`. The values are strings to display.

Example:

```elixir
defmodule NameBadge.Screen.CustomScreen do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def mount(_args, screen) do
    {:ok, assign(screen, button_hints: %{a: "Button A Hint", b: "Button B Hint"})}
  end
end
```

## Navigation

It is possible to navigate to other screens by calling the `navigate/2` function
(this function is also already imported with the `use NameBadge.Screen` macro).

Pass it a module to navigate to, or the atom `:back` to navigate up the
navigation stack.

Example:

```elixir
defmodule NameBadge.Screen.CustomScreen do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, screen) do
    {:noreply, navigate(screen, NameBadge.Screen.CustomScreen2)}
  end

  def handle_button(:button_2, :single_press, screen) do
    {:noreply, navigate(screen, :back)}
  end
end
```
