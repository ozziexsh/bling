defmodule BlingTest.ExampleBling do
  @behaviour Bling

  def can_manage_billing?(_conn, _customer) do
    true
  end

  def handle_stripe_webhook_event(_event) do
    :ok
  end

  def tax_rate_ids(_customer) do
    []
  end

  def to_stripe_params(customer) do
    %{email: customer.email}
  end
end
