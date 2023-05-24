defmodule BlingTest.ExampleBling do
  # this results in compilation errors "Bling.Entity is not a protocol"
  # help??
  #
  # use Bling,
  #   repo: BlingTest.Repo,
  #   customers: [user: BlingTest.User],
  #   subscriptions: BlingTest.Subscription,
  #   subscription_item: BlingTest.SubscriptionItem

  # instead we have to manually implement the methods...
  def customers, do: [user: BlingTest.User]
  def repo, do: BlingTest.Repo
  def subscription, do: BlingTest.Subscription
  def subscription_item, do: BlingTest.SubscriptionItem

  def module_from_customer_type(type) do
    Enum.find_value(customers(), fn {name, mod} ->
      if to_string(name) == to_string(type), do: mod, else: nil
    end)
  end

  def customer_type_from_struct(customer) do
    Enum.find_value(customers(), fn {name, mod} ->
      if customer.__struct__ == mod, do: to_string(name), else: nil
    end)
  end

  def customer_from_stripe_id(stripe_id) do
    Enum.find_value(customers(), fn {_, schema} ->
      repo().get_by(schema, stripe_id: stripe_id)
    end)
  end
end
