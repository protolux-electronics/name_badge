defmodule NameBadge.Screen.Gallery do
  use NameBadge.Screen

  require Logger

  alias NameBadge.Socket

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

  def mount(_args, screen) do
    Socket.join_gallery()

    {:ok, screen}
  end

  def handle_button(_, 0, screen) do
    Socket.leave_gallery()
    NameBadge.Device.navigate_back()
    {:ok, screen}
  end

  def handle_button(_, _, screen) do
    {:ok, screen}
  end
end
