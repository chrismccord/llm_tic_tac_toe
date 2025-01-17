defmodule TicTacToe.GameServer do
  use GenServer

  alias Phoenix.PubSub
  alias TicTacToe.PubSub, as: TicTacToePubSub

  @topic "game:lobby"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    {:ok, %{players: %{}, board: List.duplicate(nil, 9), current_player: nil, winner: nil}}
  end

  def join(player_pid) do
    GenServer.call(__MODULE__, {:join, player_pid})
  end

  def move(player_pid, index) do
    GenServer.call(__MODULE__, {:move, player_pid, index})
  end

  def get_players() do
    GenServer.call(__MODULE__, :get_players)
  end

  def current_player() do
    GenServer.call(__MODULE__, :current_player)
  end

  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  def get_player(player_pid) do
    GenServer.call(__MODULE__, {:get_player, player_pid})
  end

  def winner() do
    GenServer.call(__MODULE__, :winner)
  end

  def handle_call({:join, player_pid}, _from, state) do
    require Logger
    Logger.debug("Player joined: #{inspect(player_pid)}. Current players: #{map_size(state.players)}")

    # First, process any pending :DOWN messages to clean up dead players
    state = process_pending_down_messages(state)

    case map_size(state.players) do
      0 ->
        Logger.debug("First player joined. Setting awaiting_player to true")
        Process.monitor(player_pid)
        new_state = %{state | players: Map.put(state.players, player_pid, "X"), current_player: "X"}
        PubSub.broadcast(TicTacToePubSub, @topic, {:player_joined, true})
        {:reply, {:ok, "X"}, new_state}

      1 ->
        Logger.debug("Second player joined. Setting awaiting_player to false")
        Process.monitor(player_pid)
        new_state = %{state | players: Map.put(state.players, player_pid, "O")}
        PubSub.broadcast(TicTacToePubSub, @topic, {:player_joined, false})
        {:reply, {:ok, "O"}, new_state}

      _ ->
        Logger.debug("Game is full. Rejecting player")
        {:reply, {:error, :game_full}, state}
    end
  end

  def handle_call(:get_players, _from, state) do
    {:reply, state.players, state}
  end

  def handle_call(:current_player, _from, state) do
    {:reply, state.current_player, state}
  end

  def handle_call(:reset, _from, state) do
    require Logger
    Logger.debug("Resetting game state while keeping players")

    # Randomly select the starting player for the new match
    starting_player = Enum.random(["X", "O"])

    # Reset the board, winner, and current_player while keeping the players
    new_state = %{state |
      board: List.duplicate(nil, 9),
      winner: nil,
      current_player: starting_player
    }

    # Broadcast the reset to all players
    PubSub.broadcast(TicTacToePubSub, @topic, {:game_reset, new_state.board})

    {:reply, :ok, new_state}
  end

  def handle_call({:move, player_pid, index}, _from, state) do
    require Logger
    Logger.debug("Player #{inspect(player_pid)} attempting move at index #{index}")

    case state.players[player_pid] do
      nil ->
        Logger.debug("Invalid player attempting move")
        {:reply, {:error, :invalid_player}, state}

      player ->
        if state.winner do
          Logger.debug("Game already won. Ignoring move")
          {:reply, {:error, :game_over}, state}
        else
          case Enum.at(state.board, index) do
            nil ->
              Logger.debug("Valid move. Updating board")
              new_board = List.replace_at(state.board, index, player)
              # Alternate the current player after each move
              next_player = if player == "X", do: "O", else: "X"
              new_state = %{state | board: new_board, current_player: next_player}

              # Check for a winner or draw after the move
              case check_winner(new_board) do
                {:winner, winner} ->
                  Logger.debug("Winner detected: #{winner}")
                  # Broadcast the move first, then the winner
                  PubSub.broadcast(TicTacToePubSub, @topic, {:move_made, player, index})
                  new_state = %{new_state | winner: winner}
                  PubSub.broadcast(TicTacToePubSub, @topic, {:winner, winner})
                  {:reply, :ok, new_state}

                :draw ->
                  Logger.debug("Draw detected")
                  # Broadcast the move first, then the draw
                  PubSub.broadcast(TicTacToePubSub, @topic, {:move_made, player, index})
                  new_state = %{new_state | winner: :tie}
                  PubSub.broadcast(TicTacToePubSub, @topic, {:winner, :tie})
                  {:reply, :ok, new_state}

                :no_winner ->
                  PubSub.broadcast(TicTacToePubSub, @topic, {:move_made, player, index})
                  {:reply, :ok, new_state}
              end

            _ ->
              Logger.debug("Invalid move - position already taken")
              {:reply, {:error, :position_taken}, state}
          end
        end
    end
  end

  def handle_call({:get_player, player_pid}, _from, state) do
    player = Map.get(state.players, player_pid)
    {:reply, player, state}
  end

  def handle_call(:winner, _from, state) do
    {:reply, state.winner, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    require Logger
    Logger.debug("Player disconnected: #{inspect(pid)}")

    # Remove the disconnected player and reset the game state
    new_players = Map.delete(state.players, pid)
    new_state = %{state |
      players: new_players,
      board: List.duplicate(nil, 9),
      winner: nil,
      current_player: nil
    }

    # Notify remaining players and update awaiting_player state
    awaiting_player = map_size(new_players) < 2
    PubSub.broadcast(TicTacToePubSub, @topic, {:player_left, awaiting_player})

    {:noreply, new_state}
  end

  defp check_winner(board) do
    # Define all possible winning combinations
    winning_combinations = [
      # Rows
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      # Columns
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      # Diagonals
      [0, 4, 8],
      [2, 4, 6]
    ]

    # Check each winning combination
    case Enum.find_value(winning_combinations, :no_winner, fn [a, b, c] ->
      if Enum.at(board, a) && Enum.at(board, a) == Enum.at(board, b) && Enum.at(board, a) == Enum.at(board, c) do
        {:winner, Enum.at(board, a)}
      end
    end) do
      :no_winner ->
        # If no winner, check if the board is full (draw)
        if Enum.all?(board, & &1) do
          :draw
        else
          :no_winner
        end

      winner ->
        winner
    end
  end

  defp process_pending_down_messages(state) do
    receive do
      {:DOWN, _ref, :process, pid, _reason} ->
        require Logger
        Logger.debug("Processing pending DOWN message for player: #{inspect(pid)}")
        new_players = Map.delete(state.players, pid)
        new_state = %{state |
          players: new_players,
          board: List.duplicate(nil, 9),
          winner: nil,
          current_player: nil
        }
        # Notify remaining players and update awaiting_player state
        awaiting_player = map_size(new_players) < 2
        PubSub.broadcast(TicTacToePubSub, @topic, {:player_left, awaiting_player})
        process_pending_down_messages(new_state)
    after
      0 -> state
    end
  end
end
