defmodule TicTacToe.GameSupervisor do
  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_game(game_id) do
    DynamicSupervisor.start_child(__MODULE__, {TicTacToe.GameServer, game_id})
  end
end
