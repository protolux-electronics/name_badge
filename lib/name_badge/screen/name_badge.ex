defmodule NameBadge.Screen.NameBadge do
  use NameBadge.Screen

  require Logger

  @impl NameBadge.Screen
  def mount(_args, screen) do
    Logger.error("hello from Name Badge screen")

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(_button, _press_type, screen) do
    {:noreply, navigate(screen, :back)}
  end
end
