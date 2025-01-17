defmodule TicTacToeWeb.GameLive do
  use TicTacToeWeb, :live_view

  alias TicTacToe.GameServer
  alias Phoenix.PubSub
  alias TicTacToe.PubSub, as: TicTacToePubSub

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    require Logger
    topic = "game:#{game_id}"
    Logger.debug("Mounting GameLive for game #{game_id}. Subscribing to topic: #{topic}")

    socket =
      socket
      |> assign(:game_id, game_id)
      |> assign(:player, nil)
      |> assign(:players, %{})
      |> assign(:current_player, nil)
      |> assign(:board, List.duplicate(nil, 9))
      |> assign(:winner, nil)
      |> assign(:game_full, false)
      |> assign(:awaiting_player, true)

    if connected?(socket) do
      PubSub.subscribe(TicTacToePubSub, topic)

      case GameServer.start_or_get(game_id) do
        {:ok, _game_server} ->
          case GameServer.join(game_id, self()) do
            {:ok, player} ->
              players = GameServer.get_players(game_id)
              current_player = GameServer.current_player(game_id)

              socket =
                socket
                |> assign(:player, player)
                |> assign(:players, players)
                |> assign(:current_player, current_player)
                |> assign(:awaiting_player, Kernel.map_size(players) < 2)

              {:ok, socket}

            {:error, :game_full} ->
              {:ok, assign(socket, game_full: true)}
          end

        {:error, reason} ->
          Logger.error("Failed to start or get game server: #{inspect(reason)}")
          {:ok, assign(socket, game_full: true)}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("move", %{"index" => index}, socket) do
    index = String.to_integer(index)
    game_id = socket.assigns.game_id

    case GameServer.move(game_id, socket.assigns.player, index) do
      :ok -> {:noreply, socket}
      {:error, :invalid_move} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do

    game_id = socket.assigns.game_id
    GameServer.reset(game_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:move_made, _player, _index, board}, socket) do
    current_player = GameServer.current_player(socket.assigns.game_id)
    {:noreply, assign(socket, board: board, current_player: current_player)}
  end

  @impl true
  def handle_info({:winner, winner}, socket) do
    {:noreply, assign(socket, winner: winner)}
  end

  @impl true
  def handle_info({:game_reset, board}, socket) do
    current_player = GameServer.current_player(socket.assigns.game_id)
    {:noreply, assign(socket, board: board, winner: nil, current_player: current_player)}
  end

  @impl true
  def handle_info({:player_left, _player_pid}, socket) do
    {:noreply, assign(socket, awaiting_player: true)}
  end

  @impl true
  def handle_info({:player_joined, _player_pid}, socket) do
    players = GameServer.get_players(socket.assigns.game_id)
    current_player = GameServer.current_player(socket.assigns.game_id)

    socket =
      socket
      |> assign(:players, players)
      |> assign(:current_player, current_player)
      |> assign(:awaiting_player, false)

    {:noreply, socket}
  end

  def cell_classes(current_player, player, winner, cell) do
    cond do
      winner && cell == player -> "bg-green-200"
      cell == "X" -> "text-purple-600"
      cell == "O" -> "text-orange-500"
      current_player == player -> "bg-blue-100 hover:bg-blue-200"
      true -> "bg-gray-100 hover:bg-gray-200"
    end
  end
end
