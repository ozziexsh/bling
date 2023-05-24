defmodule Mix.Tasks.Bling.Customer do
  @moduledoc """
  This task creates a migration to add the required customer columns to an existing table.

  ## Usage

      mix bling.customer <table>
      mix bling.customer users
      mix bling.customer teams
  """
  @shortdoc "Creates a migration to add the required customer columns to an existing table."

  use Mix.Task

  def run([table]) do
    project_directory = Mix.Project.build_path() |> String.split("_build") |> List.first()
    dep_directory = Mix.Project.deps_paths(depth: 1) |> Map.fetch!(:bling)
    module_name = Mix.Project.get() |> to_string() |> String.split(".") |> Enum.at(1)

    stub_path = Path.join([dep_directory, "stubs/customer_migration.exs.stub"])

    final_path =
      Path.join([
        project_directory,
        "priv/repo/migrations/#{get_migration_timestamp()}_#{table}_customer_migration.exs"
      ])

    Mix.Generator.copy_template(stub_path, final_path,
      module_name: module_name,
      table_name: table,
      schema_name: String.capitalize(table)
    )

    Mix.Shell.IO.info("""
    Make sure to finish setting up the customer as per the documentation:

    https://hexdocs.pm/bling/readme.html#customers
    """)
  end

  defp get_migration_timestamp() do
    DateTime.utc_now()
    |> to_string()
    |> String.split(".")
    |> List.first()
    |> String.replace("-", "")
    |> String.replace(":", "")
    |> String.replace(" ", "")
  end
end
