defmodule NameBadge.DisplayMock do
  use GenServer

  def subscribe(), do: Registry.register(NameBadge.Registry, :frame_updates, nil)

  def send_frame(png) do
    Registry.dispatch(NameBadge.Registry, :frame_updates, fn pids ->
      for {pid, _value} <- pids, do: send(pid, {:frame, png})
    end)
  end

  def get_current_frame() do
    GenServer.call(NameBadge.Display, :get_current_frame)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: NameBadge.Display)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, initial_frame()}
  end

  @impl GenServer
  def handle_call({:render_typst, markup, _opts}, _from, _state) do
    png =
      markup
      |> NameBadge.Display.eval_template()
      |> prepare_png()

    send_frame(png)

    {:reply, :ok, png}
  end

  @impl GenServer
  def handle_call({:render_png, png_ref_or_binary, _opts}, _from, _state) do
    png =
      case png_ref_or_binary do
        bin when is_binary(bin) -> bin
        ref when is_reference(ref) -> Dither.encode!(ref)
      end
      |> prepare_png()

    send_frame(png)

    {:reply, :ok, png}
  end

  @impl GenServer
  def handle_call(:get_current_frame, _from, state) do
    {:reply, state, state}
  end

  defp initial_frame() do
    """
    #set page(width: 400pt, height: 300pt)
    #place(center + horizon, image("images/logos.svg", width: 196pt))
    """
    |> Typst.render_to_png!([], root_dir: Application.app_dir(:name_badge, "priv/typst"))
    |> List.first()
  end

  defp prepare_png(png) do
    Dither.decode!(png)
    |> Dither.grayscale!()
    |> Dither.to_raw!()
    |> threshold()
    |> Dither.from_raw!(400, 300)
    |> Dither.encode!()
  end

  defp threshold(bin) when is_binary(bin) do
    for <<b <- bin>>, into: <<>>, do: <<threshold(b)>>
  end

  defp threshold(val) when is_integer(val) and val > 100, do: 255
  defp threshold(val) when is_integer(val) and val <= 100, do: 0
end
