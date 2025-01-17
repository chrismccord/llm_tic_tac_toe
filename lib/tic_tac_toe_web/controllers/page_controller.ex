defmodule TicTacToeWeb.PageController do
  use TicTacToeWeb, :controller

  def redirect_to_random_game(conn, _params) do
    game_id = Ecto.UUID.generate()
    redirect(conn, to: ~p"/play/#{game_id}")
  end
end
