defmodule NameBadge.Screen.Settings do
  use NameBadge.Screen

  require Logger

  def render(_assigns) do
    """
    #place(center + horizon,
      stack(dir: ttb, text(size: 64pt, font: "New Amsterdam", "TODO"))
    );
    """
  end

  def init(_args) do
    {:ok, %{}}
  end

  def handle_button(_, 0, screen) do
    {:render, navigate(screen, :back)}
  end

  def handle_button(_, _, screen) do
    {:norender, screen}
  end
end
