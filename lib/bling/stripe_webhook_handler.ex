defmodule Bling.StripeWebhookHandler do
  @moduledoc """
  Handles Stripe webhooks for:
  - customer.deleted
    - cancels all subscriptions and removes the payment method
  - customer.updated
    - updates the default payment method
  - customer.subscription.created
    - creates a new subscription and subscription items
  - customer.subscription.updated
    - updates the subscription
  - customer.subscription.deleted
    - cancels the subscription

  Additional events can be handled by implementing the `handle_stripe_webhook_event/1` function in your Bling module.

  ## Usage

  Register this module before the `Parsers` plug in your `endpoint.ex` file:

      defmodule MyAppWeb.Endpoint do
        # ...

        # this MUST be added right BEFORE the parser
        plug Stripe.WebhookPlug,
          at: "/webhooks/stripe",
          handler: Bling.StripeWebhookHandler,
          secret: {Application, :get_env, [:stripity_stripe, :webhook_secret]}

        # this should already be present
        plug Plug.Parsers,
          parsers: [:urlencoded, :multipart, :json],
          pass: ["*/*"],
          json_decoder: Phoenix.json_library()

  Your config should have a webhook_secret key as well:

      config :stripity_stripe, api_key: "...", public_key: "...", webhook_secret: "..."
  """

  alias Bling.Customers
  alias Bling.Subscriptions

  def handle_event(event) do
    bling = Bling.bling()

    handle(event.type, event.data.object)

    Bling.Util.maybe_call({bling, :handle_stripe_webhook_event, [event]})
  end

  defp handle("customer.deleted", %Stripe.Customer{} = event) do
    customer = Bling.customer_from_stripe_id(event.id)

    if !customer do
      :ok
    else
      customer
      |> Customers.subscriptions()
      |> Enum.each(&Subscriptions.mark_as_cancelled/1)

      customer
      |> Ecto.Changeset.change(%{
        stripe_id: nil,
        payment_id: nil,
        payment_last_four: nil,
        payment_type: nil
      })
      |> Bling.repo().update!()

      :ok
    end
  end

  defp handle("customer.updated", %Stripe.Customer{} = event) do
    customer = Bling.customer_from_stripe_id(event.id)
    Customers.update_default_payment_method_from_stripe(customer)

    :ok
  end

  defp handle("customer.subscription.created", %Stripe.Subscription{} = event) do
    repo = Bling.repo()
    sub_schema = Bling.subscription()
    existing = repo.get_by(sub_schema, stripe_id: event.id)

    if existing do
      :ok
    else
      customer = Bling.customer_from_stripe_id(event.customer)

      subscription =
        customer
        |> Ecto.build_assoc(:subscriptions)
        |> Subscriptions.subscription_struct_from_stripe_subscription(event)
        |> repo.insert!()

      subscription_items =
        Subscriptions.subscription_item_structs_from_stripe_items(event.items.data, subscription)

      Enum.each(subscription_items, fn item -> repo.insert!(item) end)

      :ok
    end
  end

  defp handle("customer.subscription.deleted", %Stripe.Subscription{} = event) do
    repo = Bling.repo()
    sub_schema = Bling.subscription()
    subscription = repo.get_by(sub_schema, stripe_id: event.id)

    if !subscription do
      :ok
    else
      Subscriptions.mark_as_cancelled(subscription)

      :ok
    end
  end

  defp handle("customer.subscription.updated", %Stripe.Subscription{} = event) do
    repo = Bling.repo()
    sub_schema = Bling.subscription()
    sub_item_schema = Bling.subscription_item()
    subscription = repo.get_by(sub_schema, stripe_id: event.id)

    if !subscription do
      nil
    else
      status = event.status

      if status == "incomplete_expired" do
        repo.delete(subscription)

        :ok
      else
        subscription =
          subscription
          |> Subscriptions.subscription_struct_from_stripe_subscription(event)
          |> repo.update!()

        subscription_items =
          Subscriptions.subscription_item_structs_from_stripe_items(
            event.items.data,
            subscription
          )

        # insert new items, update any items that may have changed
        Enum.each(subscription_items, fn item ->
          repo.insert!(item, on_conflict: :replace_all, conflict_target: [:stripe_id])
        end)

        import Ecto.Query, only: [from: 2]

        # delete any that may have been removed
        item_ids = Enum.map(event.items.data, & &1.id)

        from(s in sub_item_schema,
          where: s.subscription_id == ^subscription.id,
          where: s.stripe_id not in ^item_ids
        )
        |> repo.delete_all()

        :ok
      end
    end
  end

  defp handle("invoice.payment_action_required", %Stripe.Invoice{} = _invoice) do
    :ok
  end

  defp handle("invoice.payment.failed", %Stripe.Invoice{} = _invoice) do
    :ok
  end

  defp handle(_event_name, _event_object), do: :ok
end
