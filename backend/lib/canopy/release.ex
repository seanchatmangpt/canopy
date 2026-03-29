defmodule Canopy.Release do
  @moduledoc false
  @app :canopy

  @doc "Run database migrations (container / release entrypoint)."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(@app)
  end
end
