defmodule BlingTest.SubscriptionItem do
  use Ecto.Schema

  schema "subscription_items" do
    field(:stripe_id, :string)
    field(:stripe_product_id, :string)
    field(:stripe_price_id, :string)
    field(:quantity, :integer)
    belongs_to(:subscription, BlingTest.Subscription)

    timestamps(type: :utc_datetime)
  end

  defimpl Bling.Entity do
    def repo(_entity), do: BlingTest.Repo
    def bling(_), do: BlingTest.ExampleBling
  end
end
