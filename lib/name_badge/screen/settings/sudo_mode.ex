defmodule NameBadge.Screen.Settings.SudoMode do
  use NameBadge.Screen

  require Logger

  @impl NameBadge.Screen
  def render(assigns) do
    Enum.at(assigns.frames, assigns.index)
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    frames =
      Application.app_dir(:name_badge, "priv/sudo_mode.bin")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.map(&Dither.from_raw!(&1, 400, 300))

    send(self(), :render)

    screen = assign(screen, frames: frames, index: 0)
    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_info(:render, screen) do
    case screen.assigns.index + 1 do
      new_index when new_index < length(screen.assigns.frames) ->
        send(self(), :render)
        {:noreply, assign(screen, index: new_index)}

      _invalid_index ->
        {:noreply, navigate(screen, :back)}
    end
  end
end
