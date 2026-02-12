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
      <script src="https://cdn.tailwindcss.com"></script>
      <script>
        tailwind.config = {
          theme: {
            extend: {
              fontFamily: {
                sans: ['Helvetica', 'Arial', 'sans-serif']
              }
            }
          }
        }
      </script>

      <div class={[
        "m-0 p-8 bg-gray-100 font-sans",
        "flex flex-col justify-center items-center",
        "min-h-screen w-full"
      ]}>
        <img 
          src={@current_frame} 
          class={[
            "border border-gray-300 rounded",
            "w-[95vw] h-auto max-w-[1200px] max-h-[80vh]"
          ]} 
        />

        <div class={["flex gap-3 mt-4"]}>
          <button 
            phx-click="button_1" 
            phx-value-press_type="long_press" 
            class={[
              "min-w-16 px-4 py-2 border border-gray-300 rounded bg-white cursor-pointer font-bold",
              "transition-all duration-100 ease-in-out hover:bg-gray-50 hover:border-gray-600",
              "active:scale-95 active:bg-gray-200"
            ]}>
            A (Long)
          </button>
          <button 
            phx-click="button_1" 
            phx-value-press_type="single_press" 
            class={[
              "min-w-16 px-4 py-2 border border-gray-300 rounded bg-white cursor-pointer font-bold",
              "transition-all duration-100 ease-in-out hover:bg-gray-50 hover:border-gray-600",
              "active:scale-95 active:bg-gray-200"
            ]}>
            A
          </button>
          <button 
            phx-click="button_2" 
            phx-value-press_type="single_press" 
            class={[
              "min-w-16 px-4 py-2 border border-gray-300 rounded bg-white cursor-pointer font-bold",
              "transition-all duration-100 ease-in-out hover:bg-gray-50 hover:border-gray-600",
              "active:scale-95 active:bg-gray-200"
            ]}>
            B
          </button>
          <button 
            phx-click="button_2" 
            phx-value-press_type="long_press" 
            class={[
              "min-w-16 px-4 py-2 border border-gray-300 rounded bg-white cursor-pointer font-bold",
              "transition-all duration-100 ease-in-out hover:bg-gray-50 hover:border-gray-600",
              "active:scale-95 active:bg-gray-200"
            ]}>
            B (Long)
          </button>
        </div>
        <p class={["mt-4 text-[0.6rem]"]}>
          Simulator was contributed by <a href="https://github.com/matthias-maennich" class={["text-[navy] no-underline hover:underline"]}>Matthias Männich</a>. Thanks Matthias!
        </p>
      </div>
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
