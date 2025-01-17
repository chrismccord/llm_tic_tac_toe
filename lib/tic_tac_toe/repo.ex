defmodule TicTacToe.Repo do
  use Ecto.Repo,
    otp_app: :tic_tac_toe,
    adapter: Ecto.Adapters.SQLite3
end
