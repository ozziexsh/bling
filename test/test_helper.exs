ExUnit.start()
Faker.start()

{:ok, _pid} = BlingTest.Repo.start_link()
{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(BlingTest.Repo, :temporary)

Ecto.Adapters.SQL.Sandbox.mode(BlingTest.Repo, :manual)
