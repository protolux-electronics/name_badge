if Mix.target() == :host do
  defmodule NameBadge.PreviewLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      Phoenix.PubSub.subscribe(NameBadge.PubSub, "display:frame")
      {:ok, assign(socket, current_frame: frame_to_data_url(NameBadge.DisplayMock.get_current_frame()))}
    end

    def render(assigns) do
      ~H"""
      <div class="container">
        <img src={@current_frame} class="frame-image"/>

        <div class="controls">
          <button phx-click="button_a" class="btn">A</button>
          <button phx-click="button_b" class="btn">B</button>
        </div>
      </div>

      <style type="text/css">
        body {
          margin: 0;
          padding: 2rem;
          background: #f5f5f5;
        }
        .container {
          display: flex;
          flex-direction: column;
          align-items: center;
        }
        .frame-image {
          border: 1px solid #ddd;
          border-radius: 4px;
        }
        .controls {
          display: flex;
          gap: 0.75rem;
          margin-top: 1rem;
        }
        .btn {
          min-width: 4rem;
          padding: 0.5rem 1rem;
          border: 1px solid #ddd;
          border-radius: 4px;
          background: white;
          cursor: pointer;
          font-weight: 700;
          transition: all 0.1s ease;
        }
        .btn:hover {
          background: #f9f9f9;
          border-color: #999;
        }
        .btn:active {
          transform: scale(0.95);
          background: #e0e0e0;
        }
      </style>
      """
    end

    def handle_info({:frame, packed_binary}, state) do
      {:noreply, assign(state, :current_frame, frame_to_data_url(packed_binary))}
    end

    def handle_event("button_a", _params, socket) do
      NameBadge.RendererMock.live_button_pressed("BTN_1")
      {:noreply, socket}
    end

    def handle_event("button_b", _params, socket) do
      NameBadge.RendererMock.live_button_pressed("BTN_2")
      {:noreply, socket}
    end

    defp frame_to_data_url(frame) do
      encoded_png =
        frame
        |> unpack_bits()
        |> :erlang.binary_to_list()
        |> Dither.NIF.from_raw(400, 300)
        |> then(fn {:ok, ref} -> Dither.encode!(ref) end)
        |> Base.encode64()

      "data:image/png;base64," <> encoded_png
    end

    defp unpack_bits(packed_binary) do
      for <<bit::1 <- packed_binary>>, into: <<>> do
        <<if(bit == 1, do: 255, else: 0)>>
      end
    end
  end
end
