defmodule Pmtr.Repo.Migrations.CreateSubscriptionItemsTable do
  use Ecto.Migration

  def change do
    create table(:subscription_items) do
      add :subscription_id, references(:subscriptions, on_delete: :delete_all), null: false
      add :stripe_id, :string, null: false
      add :stripe_product_id, :string, null: false
      add :stripe_price_id, :string, null: false
      add :quantity, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscription_items, [:stripe_id])
  end
end
