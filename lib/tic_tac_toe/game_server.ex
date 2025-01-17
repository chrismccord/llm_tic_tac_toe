defmodule TicTacToe.GameServer do
  use GenServer

  alias Phoenix.PubSub
  alias TicTacToe.PubSub, as: TicTacToePubSub

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def via_tuple(game_id) do
    {:via, Registry, {TicTacToe.GameRegistry, game_id}}
  end

  def start_or_get(game_id) do
    case Registry.lookup(TicTacToe.GameRegistry, game_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> DynamicSupervisor.start_child(TicTacToe.GameSupervisor, {__MODULE__, game_id})
    end
  end

  def init(game_id) do
    {:ok, %{game_id: game_id, players: %{}, board: List.duplicate(nil, 9), current_player: nil, winner: nil}}
  end

  def join(game_id, player_pid) do
    GenServer.call(via_tuple(game_id), {:join, player_pid})
  end

  def awaiting_player?(game_id) do
    GenServer.call(via_tuple(game_id), :awaiting_player?)
  end

  def game_full?(game_id) do
    GenServer.call(via_tuple(game_id), :game_full?)
  end

  def move(game_id, player, index) do
    GenServer.call(via_tuple(game_id), {:move, player, index})
  end

  def reset(game_id) do
    GenServer.call(via_tuple(game_id), :reset)
  end

  def get_players(game_id) do
    GenServer.call(via_tuple(game_id), :get_players)
  end

  def current_player(game_id) do
    GenServer.call(via_tuple(game_id), :current_player)
  end

  def get_board(game_id) do
    GenServer.call(via_tuple(game_id), :get_board)
  end

  def handle_call({:join, player_pid}, _from, state) do
    # Check for any pending :DOWN messages first
    state = process_pending_downs(state)

    case Kernel.map_size(state.players) do
      0 ->
        Process.monitor(player_pid)
        {:reply, {:ok, "X"}, %{state | players: Map.put(state.players, player_pid, "X")}}
      1 ->
        Process.monitor(player_pid)
        broadcast(state.game_id, {:player_joined, player_pid})
        {:reply, {:ok, "O"}, %{state | players: Map.put(state.players, player_pid, "O"), current_player: "X"}}
      _ ->
        {:reply, {:error, :game_full}, state}
    end
  end

  def handle_call(:awaiting_player?, _from, state) do
    state = process_pending_downs(state)
    {:reply, Kernel.map_size(state.players) < 2, state}
  end

  def handle_call(:game_full?, _from, state) do
    state = process_pending_downs(state)
    {:reply, Kernel.map_size(state.players) >= 2, state}
  end

  def handle_call({:move, player, index}, _from, state) do
    case state.board |> Enum.at(index) do
      nil ->
        new_board = List.replace_at(state.board, index, player)
        new_state = %{state | board: new_board}
        case check_winner(new_board) do
          {:winner, winner} ->
            broadcast(state.game_id, {:winner, winner})
            {:reply, :ok, %{new_state | winner: winner}}
          :tie ->
            broadcast(state.game_id, {:winner, :tie})
            {:reply, :ok, %{new_state | winner: :tie}}
          nil ->
            broadcast(state.game_id, {:move_made, player, index, new_board})
            {:reply, :ok, %{new_state | current_player: next_player(player)}}
        end
      _ ->
        {:reply, {:error, :invalid_move}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    new_state = %{state | board: List.duplicate(nil, 9), winner: nil, current_player: Enum.random(["X", "O"])}
    broadcast(state.game_id, {:game_reset, new_state.board})
    {:reply, :ok, new_state}
  end

  def handle_call(:get_players, _from, state) do
    {:reply, state.players, state}
  end

  def handle_call(:current_player, _from, state) do
    {:reply, state.current_player, state}
  end

  def handle_call(:get_board, _from, state) do
    {:reply, state.board, state}
  end

  def handle_info({:DOWN, _ref, :process, player_pid, _reason}, state) do
    new_players = Map.delete(state.players, player_pid)
    broadcast(state.game_id, {:player_left, player_pid})

    if map_size(new_players) == 0 do
      {:stop, :normal, %{state | players: new_players}}
    else
      {:noreply, %{state | players: new_players}}
    end
  end

  defp next_player("X"), do: "O"
  defp next_player("O"), do: "X"

  defp check_winner(board) do
    winning_lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], # rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], # columns
      [0, 4, 8], [2, 4, 6]             # diagonals
    ]

    case Enum.find(winning_lines, fn line ->
      [a, b, c] = Enum.map(line, &Enum.at(board, &1))
      a && a == b && b == c
    end) do
      nil -> if Enum.any?(board, &is_nil/1), do: nil, else: :tie
      [index | _] -> {:winner, Enum.at(board, index)}
    end
  end

  defp broadcast(game_id, message) do
    PubSub.broadcast(TicTacToePubSub, "game:#{game_id}", message)
  end

  defp process_pending_downs(state) do
    receive do
      {:DOWN, _ref, :process, player_pid, _reason} ->
        new_players = Map.delete(state.players, player_pid)
        broadcast(state.game_id, {:player_left, player_pid})
        process_pending_downs(%{state | players: new_players})
    after
      0 -> state
    end
  end
end
