defmodule NameBadge.Screen do
  use GenServer

  require Logger

  alias NameBadge.ButtonMonitor
  alias NameBadge.Display
  alias NameBadge.Layout
  alias NameBadge.ScreenManager

  @type t :: %__MODULE__{module: atom(), assigns: map(), action: nil | tuple(), mount_args: any()}

  defstruct [
    :module,
    assigns: %{},
    first_render?: true,
    action: nil,
    mount_args: nil,
    last_render: %{}
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def shutdown(pid) do
    GenServer.stop(pid)
  catch
    :exit, {:noproc, _} -> :ok
  end

  def assign(screen, key, value) do
    %{screen | assigns: Map.put(screen.assigns, key, value)}
  end

  def assign(screen, keyword) do
    new_assigns = Map.new(keyword)
    %{screen | assigns: Map.merge(screen.assigns, new_assigns)}
  end

  def navigate(screen, :back) do
    %{screen | action: {:navigate, :back}}
  end

  def navigate(screen, module) do
    %{screen | action: {:navigate, module}}
  end

  @impl true
  def init(args) do
    {screen_args, mount_args} = Keyword.split(args, [:module])
    module = Keyword.fetch!(screen_args, :module)

    {:ok, %__MODULE__{module: module, mount_args: mount_args}, {:continue, :mount}}
  end

  @impl GenServer
  def handle_continue(:mount, screen) do
    {:ok, screen} = screen.module.mount(screen.mount_args, screen)
    ButtonMonitor.subscribe(:button_1)
    ButtonMonitor.subscribe(:button_2)

    process_screen(screen)
  end

  def handle_continue({:render, render_opts}, screen) do
    # this is blocking, takes about 1s
    screen.module.render(screen.assigns)
    |> case do
      # check if it is a png header
      <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = png ->
        Display.render_png(png, render_opts)

      # check if this is a dither reference
      ref when is_reference(ref) ->
        Display.render_png(ref, render_opts)

      # otherwise, assume it is a typst template
      template when is_binary(template) ->
        template
        |> Layout.app_layout(button_hints: Map.get(screen.assigns, :button_hints, %{}))
        |> Display.render_typst(render_opts)
    end

    {:noreply, %{screen | last_render: screen.assigns, first_render?: false}}
  end

  @impl GenServer
  def handle_info({:button_event, which_button, press_type}, screen) do
    screen =
      case {which_button, press_type} do
        {:button_2, :long_press} ->
          navigate(screen, :back)

        _ ->
          {:noreply, screen} = screen.module.handle_button(which_button, press_type, screen)
          screen
      end

    flush_button_events(which_button, press_type)

    process_screen(screen)
  end

  def handle_info(message, screen) do
    {:noreply, screen} = screen.module.handle_info(message, screen)

    process_screen(screen)
  end

  @impl GenServer
  def terminate(reason, screen) do
    screen.module.terminate(reason, screen)
  end

  defp process_screen(screen) do
    screen
    |> maybe_navigate()
    |> maybe_render()
  end

  defp flush_button_events(which_button, press_type) do
    # this will discard any matching events in the process mailbox.
    # If there are no matching messages in the mailbox, it returns immediately
    receive do
      {:button_event, ^which_button, ^press_type} ->
        flush_button_events(which_button, press_type)
    after
      0 ->
        :ok
    end
  end

  defp maybe_navigate(%__MODULE__{action: action} = screen) when not is_nil(action) do
    case action do
      {:navigate, :back} ->
        ScreenManager.navigate(:back)

      {:navigate, module} ->
        ScreenManager.navigate(module)
    end

    {:noreply, screen}
  end

  # if action is nil, do nothing
  defp maybe_navigate(screen), do: screen

  defp maybe_render(%__MODULE__{} = screen) do
    cond do
      screen.first_render? -> {:noreply, screen, {:continue, {:render, []}}}
      Map.equal?(screen.last_render, screen.assigns) -> {:noreply, screen}
      true -> {:noreply, screen, {:continue, {:render, [refresh_type: :partial]}}}
    end
  end

  # if we navigate, then the return will be a tuple. Just pass it on
  defp maybe_render(return), do: return

  ###################### CALLBACK ######################

  defmacro __using__(_opts) do
    quote do
      @behaviour NameBadge.Screen
      import NameBadge.Screen, only: [assign: 2, assign: 3, navigate: 2]

      # default mount
      def mount(args, screen), do: {:ok, screen}

      # default render
      def render(assigns) do
        """
        #place(center + horizon, text(size: 32pt, font: "New Amsterdam")[Hello from #{inspect(__MODULE__)}])
        """
      end

      # default handle_button
      def handle_button(_button, _press, screen), do: {:noreply, screen}

      # default handle info just prints an error message
      def handle_info(message, screen) do
        require Logger

        Logger.error("""
          #{__MODULE__} received unhandled message:

          #{inspect(message)}
           
          Implement `handle_info/2` to process messages in your screen module
        """)

        {:noreply, screen}
      end

      def terminate(_reason, screen) do
        :ok
      end

      defoverridable NameBadge.Screen
    end
  end

  @callback mount(args :: keyword(), screen :: t()) :: {:ok, t()}
  @callback render(assigns :: map()) :: String.t()
  @callback handle_button(
              which_button :: atom(),
              press_type :: :single_press | :long_press,
              screen :: t()
            ) :: t()
  @callback handle_info(message :: any(), screen :: t()) :: {:noreply, t()}
  @callback terminate(reason :: any(), screen :: t()) :: any()
end
