defmodule Pmtr.Repo.Migrations.CreateSubscriptionsTable do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :name, :string, null: false
      add :ends_at, :utc_datetime
      add :trial_ends_at, :utc_datetime
      add :stripe_id, :string
      add :stripe_status, :string
      add :customer_id, :bigserial, null: false
      add :customer_type, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:stripe_id])
  end
end
