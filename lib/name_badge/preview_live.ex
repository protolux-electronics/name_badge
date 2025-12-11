if Mix.target() == :host do
  defmodule NameBadge.PreviewLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      NameBadge.DisplayMock.subscribe()

      current_frame =
        NameBadge.DisplayMock.get_current_frame()
        |> frame_to_data_url()

      {:ok, assign(socket, current_frame: current_frame)}
    end

    def render(assigns) do
      ~H"""
      <div class="container">
        <img src={@current_frame} class="frame-image"/>

        <div class="controls">
          <button phx-click="button_1" phx-value-press_type="long_press" class="btn">A (Long)</button>
          <button phx-click="button_1" phx-value-press_type="single_press" class="btn">A</button>
          <button phx-click="button_2" phx-value-press_type="single_press" class="btn">B</button>
          <button phx-click="button_2" phx-value-press_type="long_press" class="btn">B (Long)</button>
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

    def handle_event("button_" <> _rest = button_name, %{"press_type" => press_type}, socket) do
      # technically this is unsafe. But this is only running on your local machine
      NameBadge.ButtonMonitor.send_button_press(
        String.to_atom(button_name),
        String.to_atom(press_type)
      )

      {:noreply, socket}
    end

    defp frame_to_data_url(frame) do
      "data:image/png;base64," <> Base.encode64(frame)
    end

    defp unpack_bits(packed_binary) do
      for <<bit::1 <- packed_binary>>, into: <<>> do
        <<if(bit == 1, do: 255, else: 0)>>
      end
    end
  end
end
