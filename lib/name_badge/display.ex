defmodule NameBadge.Display do
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Render a Typst template to the display.

  `opts` are passed straight to `EInk.draw/2` — notably `mode: :full | :fast | :grayscale`.
  """
  def render_typst(markup, opts \\ []) do
    GenServer.call(__MODULE__, {:render_typst, markup, opts})
  end

  @doc """
  Render a PNG (binary or Dither ref) to the display. `opts` forwarded to `EInk.draw/2`.
  """
  def render_png(png, opts \\ []) do
    GenServer.call(__MODULE__, {:render_png, png, opts})
  end

  @impl GenServer
  def init(_opts) do
    # The EInk singleton is started separately (see NameBadge.Application +
    # `config :eink`). Here we just paint the boot frame through it.
    EInk.clear(:white)
    EInk.draw(initial_frame())

    # this sleep blocks the init of other processes in the
    # supervision tree, creating a short "loading screen"
    Process.sleep(3_000)

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:render_typst, markup, opts}, _from, state) do
    eval_template(markup)
    |> Dither.decode!()
    |> EInk.draw(opts)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:render_png, png, opts}, _from, state) do
    to_dither(png)
    |> EInk.draw(opts)

    {:reply, :ok, state}
  end

  # EInk.draw treats a raw binary as already-packed pixel data, so PNG bytes must
  # be decoded into a %Dither{} first. A Dither ref is already decoded.
  defp to_dither(png) when is_binary(png), do: Dither.decode!(png)
  defp to_dither(ref) when is_reference(ref), do: ref

  defp initial_frame() do
    """
    #set page(width: 400pt, height: 300pt)
    #place(center + horizon, image("images/logos.svg", width: 196pt))
    """
    |> Typst.render_to_png!([], root_dir: Application.app_dir(:name_badge, "priv/typst"))
    |> List.first()
    |> Dither.decode!()
  end

  def eval_template(template) do
    typst_opts = [root_dir: typst_dir(), extra_fonts: [fonts_dir()]]

    Typst.render_to_png!(template, [], typst_opts)
    |> List.first()
  end

  defp typst_dir, do: Application.app_dir(:name_badge, "priv/typst")
  defp fonts_dir, do: Path.join(typst_dir(), "fonts")
end
