defmodule NameBadge.Screen.Survey do
  use NameBadge.Screen

  require Logger

  alias NameBadge.Socket

  def render(assigns) do
    """
    #place(center + horizon, text(font: "New Amsterdam", size: 36pt, "#{assigns.question}"));
    """
  end

  def mount(%{"question" => question, "token" => token}, screen) do
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
    NameBadge.Device.navigate_back()

    {:ok, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    Logger.debug("BTN 2")

    Socket.survey_response(screen.assigns.token, "no")
    NameBadge.Device.navigate_back()

    {:ok, screen}
  end

  def handle_button(_, _, screen) do
    {:ok, screen}
  end
end
