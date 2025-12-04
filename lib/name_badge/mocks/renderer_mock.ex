defmodule NameBadge.RendererMock do
  use GenServer

  require Logger

  alias NameBadge.Screen

  def live_button_pressed(which_button) do
    GenServer.cast(NameBadge.Renderer, {:live_button_pressed, which_button})
  end

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: NameBadge.Renderer)
  end

  @impl GenServer
  def init(_opts) do
    screen = %Screen{module: Screen.TopLevel}
    {:ok, screen} = Screen.TopLevel.init([], screen)

    state = %{btn_1: nil, btn_2: nil, stack: [], current_screen: screen}
    NameBadge.Renderer.handle_info({:render, :full}, state)

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:render, render_type}, state) do
    NameBadge.Renderer.handle_info({:render, render_type}, state)
  end

  @impl GenServer
  def handle_cast({:assign, key, value}, state) do
    NameBadge.Renderer.handle_cast({:assign, key, value}, state)
  end

  @impl GenServer
  def handle_cast({:survey_question, question}, state) do
    NameBadge.Renderer.handle_cast({:survey_question, question}, state)
  end

  @impl GenServer
  def handle_cast({:live_button_pressed, which_button}, state) do
    NameBadge.Renderer.handle_info({:circuits_gpio, which_button, nil, 0}, state)
  end
end
