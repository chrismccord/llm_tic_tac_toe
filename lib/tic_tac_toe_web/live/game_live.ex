defmodule TicTacToeWeb.GameLive do
  use TicTacToeWeb, :live_view

  alias TicTacToe.GameServer
  alias Phoenix.PubSub
  alias TicTacToe.PubSub, as: TicTacToePubSub

  @topic "game:lobby"

  def mount(_params, _session, socket) do
    require Logger
    Logger.debug("Mounting GameLive. Subscribing to topic: #{@topic}")

    if connected?(socket) do
      PubSub.subscribe(TicTacToePubSub, @topic)

      # Only join the game if we're connected
      case GameServer.join(self()) do
        {:ok, player} ->
          Logger.debug("Successfully joined as player: #{inspect(player)}")
          players = GameServer.get_players()
          awaiting_player = map_size(players) < 2

          socket =
            socket
            |> assign(:board, List.duplicate(nil, 9))
            |> assign(:winner, nil)
            |> assign(:game_full, false)
            |> assign(:player_left, false)
            |> assign(:awaiting_player, awaiting_player)
            |> assign(:player, player)
            |> assign(:current_player, GameServer.current_player())

          {:ok, socket}

        {:error, :game_full} ->
          Logger.debug("Game is full")
          {:ok, assign(socket, :game_full, true)}
      end
    else
      # For disconnected mounts, initialize with default state and attempt to get player
      player = GameServer.get_player(self())
      {:ok,
       socket
       |> assign(:board, List.duplicate(nil, 9))
       |> assign(:winner, nil)
       |> assign(:game_full, false)
       |> assign(:player_left, false)
       |> assign(:awaiting_player, true)
       |> assign(:player, player)}
    end
  end

  def handle_info({:player_joined, awaiting_player}, socket) do
    require Logger
    Logger.debug("Received :player_joined message. awaiting_player=#{awaiting_player}")

    {:noreply,
     socket
     |> assign(:awaiting_player, awaiting_player)
     |> assign(:current_player, GameServer.current_player())}
  end

  def handle_info({:player_left, awaiting_player}, socket) do
    require Logger
    Logger.debug("Player left. Setting awaiting_player to #{awaiting_player}")

    {:noreply,
     socket
     |> assign(:awaiting_player, awaiting_player)
     |> assign(:current_player, GameServer.current_player())}
  end

  def handle_info({:move_made, player, index}, socket) do
    require Logger
    Logger.debug("Received :move_made message. index=#{index}")

    # Update the board state with the player's character
    board = List.update_at(socket.assigns.board, index, fn _ -> player end)
    {:noreply,
     socket
     |> assign(:board, board)
     |> assign(:current_player, GameServer.current_player())
     |> assign(:winner, GameServer.winner())}
  end

  def handle_info({:winner, winner}, socket) do
    require Logger
    Logger.debug("Received :winner message. winner=#{winner}")

    {:noreply,
     socket
     |> assign(:winner, winner)}
  end

  def handle_info({:game_reset, board}, socket) do
    require Logger
    Logger.debug("Received :game_reset message. Resetting board")

    {:noreply,
     socket
     |> assign(:board, board)
     |> assign(:winner, nil)
     |> assign(:current_player, GameServer.current_player())}
  end

  def handle_event("move", %{"index" => index}, socket) do
    require Logger
    index = String.to_integer(index)

    # Only allow moves if it's the current player's turn
    if socket.assigns.current_player == socket.assigns.player do
      case GameServer.move(self(), index) do
        :ok ->
          {:noreply, socket}

        {:error, reason} ->
          Logger.debug("Move failed: #{inspect(reason)}")
          {:noreply, socket}
      end
    else
      Logger.debug("Not the current player's turn")
      {:noreply, socket}
    end
  end

  def handle_event("reset", _params, socket) do
    require Logger
    Logger.debug("Resetting game")

    GameServer.reset()
    {:noreply,
     socket
     |> assign(:board, List.duplicate(nil, 9))
     |> assign(:winner, nil)
     |> assign(:current_player, GameServer.current_player())
     |> put_flash(:info, "Game reset! Starting a new match.")}
  end

  defp cell_classes(current_player, player, winner, cell) do
    cond do
      !is_nil(winner) -> "cursor-not-allowed"
      !is_nil(cell) -> "cursor-not-allowed"
      current_player == player -> "hover:bg-gray-100 cursor-pointer"
      true -> "cursor-not-allowed"
    end
  end
end
