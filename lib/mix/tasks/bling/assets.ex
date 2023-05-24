defmodule Mix.Tasks.Bling.Assets do
  @moduledoc """
  Copies the required assets for the billing page.
  """
  @shortdoc "Copies the required assets for the billing page."

  use Mix.Task

  def run(_) do
    project_directory = Mix.Project.build_path() |> String.split("_build") |> List.first()
    dep_directory = Mix.Project.deps_paths(depth: 1) |> Map.fetch!(:bling)
    stub_path = Path.join([dep_directory, "priv/static/assets"])

    final_path =
      Path.join([
        project_directory,
        "priv/static/assets/bling"
      ])

    File.mkdir(final_path)

    Mix.Generator.copy_file(
      Path.join([stub_path, "bling.js"]),
      Path.join([final_path, "bling.js"])
    )

    Mix.Generator.copy_file(
      Path.join([stub_path, "style.css"]),
      Path.join([final_path, "style.css"])
    )
  end
end
