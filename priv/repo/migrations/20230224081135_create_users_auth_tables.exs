defmodule Demo.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :payment_id, :string, null: true
      add :payment_type, :string, null: true
      add :payment_last_four, :string, size: 4, null: true
      add :stripe_id, :string

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:stripe_id])
  end
end
