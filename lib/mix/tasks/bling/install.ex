defmodule Mix.Tasks.Bling.Install do
  @moduledoc """
  Copies the required files to use the bling package. It should only ever be ran once.

  ## Usage

      mix bling.install
  """
  @shortdoc "Copies the required files to use the bling package."

  use Mix.Task

  def run(_) do
    project_directory = Mix.Project.build_path() |> String.split("_build") |> List.first()
    dep_directory = Mix.Project.deps_paths(depth: 1) |> Map.fetch!(:bling)
    # trim elixir. from the module name
    module_name = Mix.Project.get() |> to_string() |> String.split(".") |> Enum.at(1)

    copy_subscriptions_migration(project_directory, dep_directory, module_name)
    copy_subscription_schemas(project_directory, dep_directory, module_name)
    copy_bling_module(project_directory, dep_directory, module_name)
    Mix.Task.run("bling.assets")

    Mix.Shell.IO.info("""
    Files successfully created.

    Please follow the post-install instructions in the documentation to finish:

    https://hexdocs.pm/bling/readme.html#installation
    """)
  end

  defp copy_subscriptions_migration(project_directory, dep_directory, module_name) do
    stub_path = Path.join([dep_directory, "stubs/subscriptions_migration.exs.stub"])

    final_path =
      Path.join([
        project_directory,
        "priv/repo/migrations/#{get_migration_timestamp()}_subscriptions_migration.exs"
      ])

    Mix.Generator.copy_template(stub_path, final_path, module_name: module_name)
  end

  defp copy_subscription_schemas(project_directory, dep_directory, module_name) do
    sub_stub_path = Path.join([dep_directory, "stubs/subscription_schema.ex.stub"])
    sub_item_stub_path = Path.join([dep_directory, "stubs/subscription_item_schema.ex.stub"])

    module_folder = get_module_folder(module_name)
    context_folder = Path.join([project_directory, "lib/#{module_folder}/subscriptions"])

    File.mkdir(context_folder)

    sub_final_path =
      Path.join([
        context_folder,
        "subscription.ex"
      ])

    sub_item_final_path =
      Path.join([
        context_folder,
        "subscription_item.ex"
      ])

    Mix.Generator.copy_template(sub_stub_path, sub_final_path, module_name: module_name)
    Mix.Generator.copy_template(sub_item_stub_path, sub_item_final_path, module_name: module_name)
  end

  defp copy_bling_module(project_directory, dep_directory, module_name) do
    stub_path = Path.join([dep_directory, "stubs/bling.ex.stub"])
    module_folder = get_module_folder(module_name)

    final_path =
      Path.join([
        project_directory,
        "lib/#{module_folder}/bling.ex"
      ])

    Mix.Generator.copy_template(stub_path, final_path, module_name: module_name)
  end

  defp get_module_folder(module_name) do
    module_name
    |> Macro.underscore()
    |> String.downcase()
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
