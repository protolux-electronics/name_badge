defmodule NameBadge.Screen.Gallery do
  alias NameBadge.Socket
  use NameBadge.Screen

  require Logger

  def render(_assigns) do
    """
    #place(center + horizon, stack(dir: ttb,
      v(48pt),
      text(size: 64pt, font: "New Amsterdam", "Loading..."),
      v(8pt),
      text(size: 20pt, font: "New Amsterdam", "Press any button to exit"),
      v(32pt),
      text(size:  20pt, font: "New Amsterdam", "Sponsored by:"),
      v(12pt),
      image(height: 48pt, "images/tigris_logo.svg"))
    );
    """
  end

  def init(_args) do
    Socket.join_gallery()

    {:ok, %{}}
  end

  def handle_button(_, 0, screen) do
    Socket.leave_gallery()
    {:render, navigate(screen, :back)}
  end

  def handle_button(_, _, screen) do
    {:norender, screen}
  end
end
