defmodule NameBadge.Screen.Snake do
  use NameBadge.Screen

  require Logger

  @board_size 8
  @draw_interval :timer.seconds(1.5)
  @reset_interval :timer.seconds(5)

  @zero_size @board_size - 1

  def mount(_params, screen) do
    Logger.info("Mounting Snake!")

    initial_snake = [{3, 3}, {3, 4}, {3, 5}]
    initial_target = {1, 1}

    screen =
      screen
      |> assign(
        snake: initial_snake,
        target: initial_target,
        game_won: false,
        game_over: false,
        points: 0
      )
      |> schedule_tick()

    Logger.info("Starting a new Snake game with: #{inspect(screen)}")

    {:ok, screen}
  end

  def render(assigns) do
    %{snake: snake, target: target, game_won: game_won, game_over: game_over, points: points} =
      assigns

    """
    // Configuration
    #let board-size = #{@board_size}
    #let cell-size = 18pt
    #let border-width = 1pt

    // Snake position (head to tail)
    #let snake-positions = (#{Enum.map_join(snake, ", ", &to_pixel/1)})
    #let target-position = #{to_pixel(target)}

    // Colors
    #let board-color = rgb("#fff")
    #let snake-head-color = rgb("#000")
    #let snake-body-color = rgb("#000")
    #let target-color = rgb("#000")
    #let grid-color = rgb("#000")

    // Helper function to check if a position contains snake
    #let is-snake-position(pos) = {
      snake-positions.contains(pos)
    }

    // Helper function to check if a position is snake head
    #let is-snake-head(pos) = {
      snake-positions.first() == pos
    }

    // Helper function to check if a position is target
    #let is-target-position(pos) = {
      target-position == pos
    }

    // Function to create a single cell
    #let create-cell(row, col) = {
      let pos = (col, row)
      let cell-content

      if is-target-position(pos) {
        // Target dot
        cell-content = circle(
          radius: cell-size * 0.25,
          fill: target-color,
          stroke: none
        )
      } else if is-snake-head(pos) {
        // Snake head
        cell-content = circle(
          radius: cell-size * 0.35,
          fill: snake-head-color,
          stroke: rgb("#000") + 1pt
        )
      } else if is-snake-position(pos) {
        // Snake body
        cell-content = rect(
          width: cell-size * 0.7,
          height: cell-size * 0.7,
          fill: snake-body-color,
          stroke: rgb("#000") + 1pt,
          radius: 2pt
        )
      } else {
        // Empty cell
        cell-content = []
      }

      // Cell container
      rect(
        width: cell-size,
        height: cell-size,
        fill: board-color,
        stroke: grid-color + border-width,
        radius: 1pt,
        inset: 0pt
      )[
        #align(center + horizon)[#cell-content]
      ]
    }

    // Main board function
    #let snake-board() = {
      grid(
        columns: (cell-size,) * board-size,
        rows: (cell-size,) * board-size,
        gutter: 0pt,
        ..for row in range(board-size) {
          for col in range(board-size) {
            (create-cell(row, col),)
          }
        }
      )
    }

    // Game title and board
    #align(center)[
      #text(size: 24pt, weight: "bold", font: "New Amsterdam", fill: rgb("#{if game_over, do: "#000", else: "#fff"}"))[#{if game_won, do: "Game Won!", else: "Game Over!"}]

      #v(-20pt)

      #box(
        stroke: rgb("#000") + 3pt,
      )[
        #snake-board()
      ]

      #v(-15pt)

      #text(size: 18pt, weight: "bold", font: "New Amsterdam")[Points: #{points}]
    ]
    """
  end

  defp to_pixel({x, y}), do: "(#{x}, #{y})"

  def handle_button("BTN_1", 0, screen) do
    new_direction =
      case moving_direction(screen.assigns.snake) do
        :right -> :up
        :up -> :left
        :left -> :down
        :down -> :right
      end

    screen = screen |> cancel_tick() |> update_board(new_direction)
    NameBadge.Device.render(screen, :partial)

    {:ok, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    new_direction =
      case moving_direction(screen.assigns.snake) do
        :right -> :down
        :down -> :left
        :left -> :up
        :up -> :right
      end

    screen = screen |> cancel_tick() |> update_board(new_direction)
    NameBadge.Device.render(screen, :partial)

    {:ok, screen}
  end

  def handle_button(_btn, _, screen) do
    {:ok, screen}
  end

  def handle_info(:reset, screen) do
    NameBadge.Device.navigate_back()
    {:noreply, screen}
  end

  def handle_info(:tick, screen) do
    screen = update_board(screen)

    NameBadge.Device.render(screen, :partial)

    {:noreply, screen}
  end

  defp update_board(screen, moving_direction \\ nil) do
    %{snake: snake, target: target, points: points} = screen.assigns

    moving_direction = moving_direction || moving_direction(snake)
    new_head = next_head(snake, moving_direction)
    new_target = next_target(snake, target)

    cond do
      out_of_bounds?(new_head) ->
        assign(screen, game_over: true)

      snake_bites_itself?(new_head, snake) ->
        assign(screen, game_over: true)

      new_head == target ->
        assign(screen, game_won: true, game_over: true)

      snake_eats_target?(new_head, target) ->
        assign(screen, snake: [new_head | snake], target: new_target, points: points + 1)

      true ->
        assign(screen, snake: Enum.drop([new_head | snake], -1))
    end
    |> then(fn screen ->
      if screen.assigns.game_over do
        schedule_reset()
        screen
      else
        schedule_tick(screen)
      end
    end)
  end

  defp schedule_reset() do
    Process.send_after(self(), :reset, @reset_interval)
  end

  defp schedule_tick(screen) do
    timer_ref = Process.send_after(self(), :tick, @draw_interval)
    assign(screen, :timer, timer_ref)
  end

  defp cancel_tick(screen) do
    if screen.assigns[:timer] do
      Process.cancel_timer(screen.assigns.timer)
      Logger.info("Canceled Tick Timer")
    end

    assign(screen, :timer, nil)
  end

  defp next_head([{x, y} | _rest] = _snake, moving_direction) do
    case moving_direction do
      :right -> {x + 1, y}
      :left -> {x - 1, y}
      :up -> {x, y - 1}
      :down -> {x, y + 1}
    end
  end

  defp moving_direction([{x1, y1}, {x2, y2} | _rest] = _snake) do
    cond do
      # Moving right
      x1 > x2 and y1 == y2 -> :right
      # Moving left
      x1 < x2 and y1 == y2 -> :left
      # Moving down
      x1 == x2 and y1 > y2 -> :down
      # Moving up
      x1 == x2 and y1 < y2 -> :up
    end
  end

  defp next_target(snake, target) do
    filled_cells = MapSet.new([target | snake])

    all_cells =
      0..@zero_size
      |> Enum.flat_map(fn x -> Enum.map(0..@zero_size, fn y -> {x, y} end) end)
      |> MapSet.new()

    available_cells = MapSet.difference(all_cells, filled_cells)

    Enum.random(available_cells)
  end

  defp out_of_bounds?({x, y} = _head) do
    x > @zero_size or y > @zero_size or x < 0 or y < 0
  end

  defp snake_bites_itself?(new_head, snake) do
    Enum.any?(snake, &(&1 == new_head))
  end

  defp snake_eats_target?(new_head, target) do
    new_head == target
  end
end
