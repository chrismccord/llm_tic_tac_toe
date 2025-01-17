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
      |> assign(:board, List.duplicate(nil, 9))
      |> assign(:winner, nil)
      |> assign(:game_full, false)
      |> assign(:awaiting_player, true)
      |> assign(:current_player, nil)

    if connected?(socket) do
      PubSub.subscribe(TicTacToePubSub, topic)
      case GameServer.start_or_get(game_id) do
        {:ok, _pid} ->
          case GameServer.join(game_id, self()) do
            {:ok, player} ->
              {:ok,
                socket
                |> assign(:player, player)
                |> assign(:awaiting_player, GameServer.awaiting_player?(game_id))
                |> assign(:current_player, GameServer.current_player(game_id))}

            {:error, _reason} ->
              {:ok, socket |> assign(:game_full, true)}
          end
        {:error, _reason} ->
          {:ok, socket |> assign(:game_full, true)}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("move", %{"index" => index}, socket) do
    index = String.to_integer(index)
    case GameServer.move(socket.assigns.game_id, socket.assigns.player, index) do
      :ok ->
        {:noreply, socket}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    GameServer.reset(socket.assigns.game_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:move_made, _player, _index, new_board}, socket) do
    socket =
      socket
      |> assign(:board, new_board)
      |> assign(:current_player, GameServer.current_player(socket.assigns.game_id))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:winner, winner}, socket) do
    socket =
      socket
      |> assign(:winner, winner)
      |> assign(:board, GameServer.get_board(socket.assigns.game_id))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:player_joined, _player}, socket) do
    socket =
      socket
      |> assign(:awaiting_player, false)
      |> assign(:current_player, GameServer.current_player(socket.assigns.game_id))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:player_left, _player_pid}, socket) do
    socket =
      socket
      |> assign(:awaiting_player, true)
      |> assign(:game_full, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:game_reset, new_board}, socket) do
    socket =
      socket
      |> assign(:board, new_board)
      |> assign(:winner, nil)
      |> assign(:current_player, GameServer.current_player(socket.assigns.game_id))

    {:noreply, socket}
  end

  defp cell_classes(cell) do
    base_classes = "w-24 h-24 border border-gray-400 flex items-center justify-center text-4xl font-bold rounded-lg bg-gray-300"

    case cell do
      "X" -> "#{base_classes} text-purple-600"
      "O" -> "#{base_classes} text-orange-500"
      _ -> base_classes
    end
  end
end
