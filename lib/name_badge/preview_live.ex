if Mix.target() == :host do
  defmodule NameBadge.PreviewLive do
    use Phoenix.LiveView

    @long_press_ms 500

    def mount(_params, _session, socket) do
      NameBadge.DisplayMock.subscribe()

      current_frame =
        NameBadge.DisplayMock.get_current_frame()
        |> frame_to_data_url()

      {:ok, assign(socket, current_frame: current_frame, pending_keys: %{})}
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

      <div
        class="bg-gray-100 font-sans flex flex-col justify-center items-center min-h-screen w-full p-8"
        phx-window-keydown="keydown"
        phx-window-keyup="keyup"
      >
        <img
          src={@current_frame}
          class="border border-gray-300 rounded aspect-4/3 w-full sm:w-3/4 md:w-1/2 max-w-[1200px]"
        />

        <div class="flex items-center justify-center gap-2 mt-4 w-full sm:w-3/4 md:w-1/2">
          <button
            phx-click="button_1"
            phx-value-press_type="long_press"
            class={button_class()}>
            A (Long)
          </button>
          <button
            phx-click="button_1"
            phx-value-press_type="single_press"
            class={button_class()}>
            A
          </button>
          <button
            phx-click="button_2"
            phx-value-press_type="single_press"
            class={button_class()}>
            B
          </button>
          <button
            phx-click="button_2"
            phx-value-press_type="long_press"
            class={button_class()}>
            B (Long)
          </button>
        </div>
        <p class="mt-2 text-xs text-gray-600">
          Keyboard: tap <kbd class="px-1 border rounded">A</kbd>/<kbd class="px-1 border rounded">B</kbd> for single press, hold for long press.
        </p>
        <p class="mt-4 text-[0.6rem]">
          Simulator was contributed by <a href="https://github.com/matthias-maennich" class={["text-[navy] no-underline hover:underline"]}>Matthias Männich</a>. Thanks Matthias!
        </p>
      </div>
      """
    end

    def handle_event("button_" <> _rest = button_name, %{"press_type" => press_type}, socket) do
      # technically this is unsafe. But this is only running on your local machine
      NameBadge.ButtonMonitor.send_button_press(
        String.to_atom(button_name),
        String.to_atom(press_type)
      )

      {:noreply, socket}
    end

    def handle_event("keydown", %{"key" => key} = params, socket) do
      button = key_to_button(key)
      repeat? = Map.get(params, "repeat", false)

      if (button && not repeat?) and not Map.has_key?(socket.assigns.pending_keys, button) do
        timer_ref = Process.send_after(self(), {:long_press, button}, @long_press_ms)
        pending = Map.put(socket.assigns.pending_keys, button, timer_ref)
        {:noreply, assign(socket, :pending_keys, pending)}
      else
        {:noreply, socket}
      end
    end

    def handle_event("keyup", %{"key" => key}, socket) do
      with button when not is_nil(button) <- key_to_button(key),
           {entry, new_map} when not is_nil(entry) <-
             Map.pop(socket.assigns.pending_keys, button) do
        case entry do
          :fired ->
            :ok

          timer_ref when is_reference(timer_ref) ->
            Process.cancel_timer(timer_ref)
            NameBadge.ButtonMonitor.send_button_press(button, :single_press)
        end

        {:noreply, assign(socket, :pending_keys, new_map)}
      else
        _ -> {:noreply, socket}
      end
    end

    def handle_info({:frame, packed_binary}, state) do
      {:noreply, assign(state, :current_frame, frame_to_data_url(packed_binary))}
    end

    def handle_info({:long_press, button}, socket) do
      case Map.get(socket.assigns.pending_keys, button) do
        timer_ref when is_reference(timer_ref) ->
          NameBadge.ButtonMonitor.send_button_press(button, :long_press)
          pending = Map.put(socket.assigns.pending_keys, button, :fired)
          {:noreply, assign(socket, :pending_keys, pending)}

        _ ->
          {:noreply, socket}
      end
    end

    defp key_to_button(key) do
      case String.downcase(key) do
        "a" -> :button_1
        "b" -> :button_2
        _ -> false
      end
    end

    defp frame_to_data_url(frame) do
      "data:image/png;base64," <> Base.encode64(frame)
    end

    defp button_class() do
      "flex-1 min-w-28 px-4 py-2 border border-gray-300 rounded-lg bg-white cursor-pointer font-bold transition-all duration-100 ease-in-out hover:bg-gray-50 hover:border-gray-600 active:scale-95 active:bg-gray-200"
    end
  end
end
