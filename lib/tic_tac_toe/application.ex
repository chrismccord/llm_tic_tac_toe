defmodule TicTacToe.Application do
  use Application

  def start(_type, _args) do
    children = [
      TicTacToeWeb.Telemetry,
      {Phoenix.PubSub, name: TicTacToe.PubSub},
      TicTacToe.Repo,
      TicTacToeWeb.Endpoint,
      TicTacToe.GameRegistry,
      TicTacToe.GameSupervisor
    ]

    opts = [strategy: :one_for_one, name: TicTacToe.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    TicTacToeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
