defmodule CanopyWeb.Plugs.ErrorHandler do
  @moduledoc "Catches unhandled exceptions and returns JSON error responses."
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
  rescue
    _e in Ecto.NoResultsError ->
      msg = "Resource not found. Tip: verify resource ID exists and you have permission to access it."
      conn |> put_status(404) |> json_error("not_found", msg)

    _e in Ecto.Query.CastError ->
      msg = "Invalid ID format. Tip: check query parameters are valid UUIDs or integers. See docs/TROUBLESHOOTING.md#ecto-cast-errors"
      conn |> put_status(400) |> json_error("invalid_id", msg)

    _e in Phoenix.Router.NoRouteError ->
      msg = "Endpoint not found. Tip: check the request path is spelled correctly and HTTP method matches the route definition."
      conn |> put_status(404) |> json_error("not_found", msg)

    e ->
      Logger.error(
        "[ErrorHandler] Unhandled: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      msg = "Internal server error. See docs/TROUBLESHOOTING.md for common issues. Check server logs for full stack trace."
      conn |> put_status(500) |> json_error("internal_error", msg)
  end

  defp json_error(conn, code, message) do
    body = Jason.encode!(%{error: code, details: message})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 500, body)
    |> halt()
  end
end
