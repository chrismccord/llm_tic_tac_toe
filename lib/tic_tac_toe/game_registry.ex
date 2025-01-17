defmodule TicTacToe.GameRegistry do
  @moduledoc """
  A named registry for managing game server processes by game_id.
  """
  @name __MODULE__

  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: @name, partitions: System.schedulers_online())
  end

  def via_tuple(game_id) do
    {:via, Registry, {@name, game_id}}
  end

  def lookup(game_id) do
    Registry.lookup(@name, game_id)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts
]},
      type: :supervisor
    }
  end
end
