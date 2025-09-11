defmodule NameBadge.Screen.Survey do
  alias NameBadge.Socket
  use NameBadge.Screen

  require Logger

  def render(assigns) do
    """
    #place(center + horizon, text(font: "New Amsterdam", size: 36pt, "#{assigns.question}"));
    """
  end

  def init(%{"question" => question, "token" => token}, screen) do
    screen =
      screen
      |> assign(:token, token)
      |> assign(:question, question)
      |> assign(:button_hints, %{a: "Yes", b: "No"})

    {:ok, screen}
  end

  def handle_button("BTN_1", 0, screen) do
    Logger.debug("BTN 1")
    Socket.survey_response(screen.assigns.token, "yes")
    {:render, navigate(screen, :back)}
  end

  def handle_button("BTN_2", _, screen) do
    Logger.debug("BTN 2")
    Socket.survey_response(screen.assigns.token, "no")
    {:render, navigate(screen, :back)}
  end

  def handle_button(_, _, screen) do
    {:norender, screen}
  end
end
