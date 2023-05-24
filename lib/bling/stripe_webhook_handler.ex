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

  First make sure to create a file like `my_app_web/stripe_webhook_handler.ex`:

      defmodule MyAppWeb.StripeWebhookHandler do
        use Bling.StripeWebhookHandler, bling: MyApp.Bling
      end


  Then be sure to register it before the `Parsers` plug in your `endpoint.ex` file:

      defmodule MyAppWeb.Endpoint do
        # ...

        # this MUST be added right BEFORE the parser
        plug Stripe.WebhookPlug,
          at: "/webhooks/stripe",
          handler: MyAppWeb.StripeWebhookHandler,
          secret: {Application, :get_env, [:stripity_stripe, :webhook_secret]}

        # this should already be present
        plug Plug.Parsers,
          parsers: [:urlencoded, :multipart, :json],
          pass: ["*/*"],
          json_decoder: Phoenix.json_library()

  Your config should have a webhook_secret key as well:

      config :stripity_stripe, api_key: "...", public_key: "...", webhook_key: "..."
  """

  alias Bling.Customers
  alias Bling.Subscriptions

  defmacro __using__(opts) do
    quote do
      @behaviour Stripe.WebhookHandler

      @impl true
      def handle_event(event) do
        Bling.StripeWebhookHandler.handle_event(event, unquote(opts[:bling]))
      end
    end
  end

  def handle_event(event, bling) do
    handle(event.type, event.data.object, bling)

    Bling.Util.maybe_call({bling, :handle_stripe_webhook_event, [event]})
  end

  defp handle("customer.deleted", %Stripe.Customer{} = event, bling) do
    customer = bling.customer_from_stripe_id(event.id)

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
      |> bling.repo().update!()

      :ok
    end
  end

  defp handle("customer.updated", %Stripe.Customer{} = event, bling) do
    customer = bling.customer_from_stripe_id(event.id)
    Customers.update_default_payment_method_from_stripe(customer)

    :ok
  end

  defp handle("customer.subscription.created", %Stripe.Subscription{} = event, bling) do
    repo = bling.repo()
    sub_schema = bling.subscription()
    existing = repo.get_by(sub_schema, stripe_id: event.id)

    if existing do
      :ok
    else
      customer = bling.customer_from_stripe_id(event.customer)

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

  defp handle("customer.subscription.deleted", %Stripe.Subscription{} = event, bling) do
    repo = bling.repo()
    sub_schema = bling.subscription()
    subscription = repo.get_by(sub_schema, stripe_id: event.id)

    if !subscription do
      :ok
    else
      Subscriptions.mark_as_cancelled(subscription)

      :ok
    end
  end

  defp handle("customer.subscription.updated", %Stripe.Subscription{} = event, bling) do
    repo = bling.repo()
    sub_schema = bling.subscription()
    sub_item_schema = bling.subscription_item()
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

  defp handle("invoice.payment_action_required", %Stripe.Invoice{} = _invoice, _bling) do
    :ok
  end

  defp handle("invoice.payment.failed", %Stripe.Invoice{} = _invoice, _bling) do
    :ok
  end

  defp handle(_event_name, _event_object, _bling), do: :ok
end
