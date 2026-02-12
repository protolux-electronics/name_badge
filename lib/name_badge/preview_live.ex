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
        <p class="attribution">Simulator was contributed by <a href="https://github.com/matthias-maennich">Matthias Männich</a>. Thanks Matthias!</p>
      </div>

      <style type="text/css">
        body {
          font-family: "Helvetica";
          margin: 0;
          padding: 2rem;
          background: #f5f5f5;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
        }
        .container {
          display: flex;
          flex-direction: column;
          align-items: center;
          width: 100%;
          padding: 0;
          box-sizing: border-box;
        }
        .frame-image {
          border: 1px solid #ddd;
          border-radius: 4px;
          width: 95vw;
          height: auto;
          max-width: 1200px;
          max-height: 80vh;
          object-fit: contain;
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

        .attribution {
          margin-top: 1rem;
          font-size: 0.6rem;
        }

        a {
          color: Navy;
          text-decoration: none;
        }

        a:hover {
          text-decoration: underline;
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
  end
end
