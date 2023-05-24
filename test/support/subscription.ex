defmodule BlingTest.Subscription do
  use Ecto.Schema

  schema "subscriptions" do
    field(:name, :string)
    field(:ends_at, :utc_datetime)
    field(:trial_ends_at, :utc_datetime)
    field(:stripe_id, :string)
    field(:stripe_status, :string)
    field(:customer_id, :integer)
    field(:customer_type, :string)
    has_many(:subscription_items, BlingTest.SubscriptionItem)

    timestamps(type: :utc_datetime)
  end

  defimpl Bling.Entity do
    def repo(_), do: BlingTest.Repo
    def bling(_), do: BlingTest.ExampleBling
  end
end
