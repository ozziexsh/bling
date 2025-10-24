defmodule Bling.Subscriptions do
  @moduledoc """
  Module to interact with Bling subscriptions. Most functions expect the ecto subscription struct
  as the first argument, and will return the updated subscription with subscription items preloaded.
  """

  import Ecto.Changeset, only: [change: 2]

  @default_plan "default"

  @doc """
  Returns all of the database subscription items for a subscription.
  """
  def subscription_items(subscription) do
    repo = Bling.repo()

    subscription |> repo.preload(:subscription_items) |> Map.get(:subscription_items, [])
  end

  @doc """
  Returns whether the provided subscription is valid, which is the case if any of the following checks are true:
  - `Bling.Subscriptions.active?/1`
  - `Bling.Subscriptions.trial?/1`
  - `Bling.Subscriptions.grace_period?/1`
  """
  def valid?(subscription) do
    active?(subscription) || trial?(subscription) || grace_period?(subscription)
  end

  @doc """
  Returns whether the provided subscription is active, which is if it has not ended, and it has a valid status.
  """
  def active?(subscription) do
    !ended?(subscription) &&
      !Enum.member?(
        ["incomplete", "incomplete_expired", "past_due", "unpaid"],
        subscription.stripe_status
      )
  end

  @doc """
  Returns whether the provided subscription is on a trial that hasn't expired.
  """
  def trial?(subscription) do
    ends_at =
      subscription.trial_ends_at &&
        DateTime.compare(subscription.trial_ends_at, DateTime.utc_now())

    ends_at == :gt
  end

  @doc """
  Returns whether the provided subcription has been cancelled but has time before it ends.
  """
  def grace_period?(subscription) do
    ends_at = subscription.ends_at && DateTime.compare(subscription.ends_at, DateTime.utc_now())
    ends_at == :gt
  end

  @doc """
  Returns whether the provided subscription has been cancelled.
  """
  def canceled?(subscription) do
    !is_nil(subscription.ends_at)
  end

  @doc """
  Returns whether the provided subscription has been cancelled and is no longer within its grace period.
  """
  def ended?(subscription) do
    canceled?(subscription) && !grace_period?(subscription)
  end

  @doc """
  Returns whether the provided subscription is recurring, which is the case if it has no end date and is not on a trial.
  """
  def recurring?(subscription) do
    is_nil(subscription.ends_at) && !trial?(subscription)
  end

  @doc """
  Returns whether the provided subscription has multiple subscription items (prices).
  """
  def has_multiple_prices?(subscription) do
    Enum.count(subscription.subscription_items) > 1
  end

  @doc """
  Returns whether the provided subscription has only a single subscription item (price).
  """
  def has_single_price?(subscription) do
    !has_multiple_prices?(subscription)
  end

  @doc """
  Adds prices to an existing subscription. Returns the subscription with the items loaded.

  ## Examples

      add_prices(subscription, prices: [{price_id, quantity}])
  """
  def add_prices(subscription, opts) do
    prices = Keyword.get(opts, :prices, [])
    stripe_params = stripe_params(opts)
    repo = Bling.repo()

    prices
    |> Enum.map(fn {price, quantity} ->
      params =
        Map.merge(stripe_params, %{
          subscription: subscription.stripe_id,
          price: price,
          quantity: quantity
        })

      {:ok, item} = Stripe.SubscriptionItem.create(params)
      item
    end)
    |> subscription_item_structs_from_stripe_items(subscription)
    |> Enum.each(fn item -> repo.insert!(item) end)

    stripe_subscription = as_stripe_subscription(subscription)

    subscription =
      subscription
      |> change(%{
        stripe_status: stripe_subscription.status
      })
      |> repo.update!()

    reload_with_items(subscription)
  end

  @doc """
  Removes prices from a subscription. Returns the subscription with the items loaded.

  Raises if all prices are removed from a subscription.

  ## Examples

      remove_prices(subscription, prices: [price_id])
  """
  def remove_prices(subscription, opts) do
    prices = Keyword.get(opts, :prices, [])
    repo = Bling.repo()
    stripe_params = stripe_params(opts)
    items = subscription_items(subscription)
    remaining_items = Enum.count(items) - Enum.count(prices)

    if remaining_items == 0 do
      raise "Cannot remove all prices from a subscription"
    end

    Enum.each(prices, fn price_id ->
      item = Enum.find(items, fn item -> item.stripe_price_id == price_id end)

      {:ok, _} = Stripe.SubscriptionItem.delete(item.stripe_id, stripe_params)

      repo.delete!(item)
    end)

    reload_with_items(subscription)
  end

  @doc """
  Changes the subscription to new prices.

  ## Examples
      change_prices(sub, prices: [{price_id, quantity}])
  """
  def change_prices(subscription, opts \\ []) do
    prices = Keyword.get(opts, :prices, [])
    repo = Bling.repo()
    subscription_items = subscription_items(subscription)

    new_items =
      Enum.map(prices, fn {price_id, quantity} ->
        existing = Enum.find(subscription_items, fn item -> item.stripe_price_id == price_id end)
        base = %{price: price_id, quantity: quantity}

        if existing do
          Map.merge(base, %{id: existing.stripe_id})
        else
          base
        end
      end)

    deleted_items =
      subscription_items
      |> Enum.filter(fn item ->
        existing = Enum.find(new_items, fn new_item -> new_item.price == item.stripe_price_id end)
        existing == nil
      end)
      |> Enum.map(fn item -> %{id: item.stripe_id, deleted: true} end)

    items = Enum.concat(new_items, deleted_items)

    stripe_params = stripe_params(opts)
    params = Map.merge(stripe_params, %{items: items})

    {:ok, stripe_subscription} = Stripe.Subscription.update(subscription.stripe_id, params)

    subscription
    |> change(%{
      stripe_status: stripe_subscription.status,
      ends_at: nil
    })
    |> repo.update!()

    stripe_subscription.items.data
    |> Enum.each(fn item ->
      Ecto.build_assoc(subscription, :subscription_items, %{
        stripe_id: item.id,
        stripe_product_id: item.price.product,
        stripe_price_id: item.price.id,
        quantity: item.quantity
      })
      |> repo.insert!(on_conflict: :replace_all, conflict_target: [:stripe_id])
    end)

    new_item_ids = Enum.map(stripe_subscription.items.data, & &1.id)

    import Ecto.Query, only: [from: 2]

    from(si in "subscription_items",
      where: si.subscription_id == ^subscription.id,
      where: si.stripe_id not in ^new_item_ids
    )
    |> repo.delete_all()

    reload_with_items(subscription)
  end

  @doc false
  def mark_as_cancelled(subscription) do
    repo = Bling.repo()

    subscription
    |> change(%{
      stripe_status: "canceled",
      ends_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> repo.update!()
    |> reload_with_items()
  end

  @doc """
  Cancels the subscription in stripe and updates the model. Cancellation is scheduled for the end of the period.

  If the user is on a trial, they will have until the end of their trial.

  ## Examples
      subscription = cancel(subscription)

      # can pass any valid Stripe.Subscription.update/2 params
      subscription = cancel(subscription, stripe: %{ prorate: false })
  """
  def cancel(subscription, opts \\ []) do
    stripe_params = stripe_params(opts)
    params = Map.merge(stripe_params, %{cancel_at_period_end: true})

    {:ok, stripe_subscription} = Stripe.Subscription.update(subscription.stripe_id, params)

    repo = Bling.repo()

    ends_at =
      if trial?(subscription) do
        subscription.trial_ends_at
      else
        stripe_subscription.current_period_end
        |> DateTime.from_unix!()
        |> DateTime.truncate(:second)
      end

    subscription
    |> change(%{
      stripe_status: stripe_subscription.status,
      ends_at: ends_at
    })
    |> repo.update!()
    |> reload_with_items()
  end

  @doc """
  Cancels a subscription at a specific time.

  ## Examples
      subscription = cancel_at(subscription, DateTime.utc_now() |> DateTime.add(30, :day))

      # can pass any valid Stripe.Subscription.update/2 params
      subscription = cancel_at(subscription, DateTime.utc_now() |> DateTime.add(30, :day), stripe: %{ prorate: false })
  """
  def cancel_at(subscription, datetime, opts \\ []) do
    stripe_params = stripe_params(opts)
    params = Map.merge(stripe_params, %{cancel_at: datetime |> DateTime.to_unix()})

    {:ok, stripe_subscription} = Stripe.Subscription.update(subscription.stripe_id, params)

    repo = Bling.repo()

    subscription
    |> change(%{
      stripe_status: stripe_subscription.status,
      ends_at:
        stripe_subscription.cancel_at |> DateTime.from_unix!() |> DateTime.truncate(:second)
    })
    |> repo.update!()
    |> reload_with_items()
  end

  @doc """
  Cancels and ends the subscription immediately.

  ## Examples
      subscription = cancel_now(subscription)

      # can pass any valid Stripe.Subscription.cancel/2 params
      subscription = cancel_now(subscription, stripe: %{ invoice_now: true })
  """
  def cancel_now(subscription, opts \\ []) do
    {:ok, _stripe_subscription} =
      Stripe.Subscription.cancel(subscription.stripe_id, stripe_params(opts))

    mark_as_cancelled(subscription)
  end

  @doc """
  Cancels, ends, and invoices for the subscription immediately. Forwards any stripe options to Bling.Subscriptions.cancel_now/2.
  """
  def cancel_now_and_invoice(subscription, opts \\ []) do
    default_params = %{invoice_now: true}

    opts =
      Keyword.update(opts, :stripe, default_params, fn existing ->
        Map.merge(existing, default_params)
      end)

    cancel_now(subscription, opts)
  end

  @doc """
  Deletes the subscription from the database as well as cancels it in stripe.

  ## Examples
      subscription = delete(subscription)

      # can pass any valid Stripe.Subscription.cancel/2 params
      subscription = delete(subscription, stripe: %{ invoice_now: true })
  """
  def delete(subscription, opts \\ []) do
    repo = Bling.repo()
    stripe_params = stripe_params(opts)
    stripe_id = subscription.stripe_id

    items = subscription_items(subscription)
    items |> Enum.each(fn item -> repo.delete!(item.stripe_id) end)

    repo.delete!(subscription)

    Stripe.Subscription.cancel(stripe_id, stripe_params)
  end

  @doc """
  Resumes a cancelled subscription. The grace period must not have ended in order for this to succeed.

  ## Examples
      subscription = resume(subscription)

      # can pass any valid Stripe.Subscription.update/2 params
      subscription = resume(subscription, stripe: %{ prorate: false })
  """
  def resume(subscription, opts \\ []) do
    stripe_params = stripe_params(opts)

    params =
      Map.merge(stripe_params, %{
        cancel_at_period_end: false,
        trial_end:
          if(trial?(subscription), do: DateTime.to_unix(subscription.trial_ends_at), else: :now)
      })

    {:ok, stripe_subscription} = Stripe.Subscription.update(subscription.stripe_id, params)

    repo = Bling.repo()

    subscription
    |> change(%{
      stripe_status: stripe_subscription.status,
      ends_at: nil
    })
    |> repo.update!()
    |> reload_with_items()
  end

  @doc """
  Fetches the stripe subscription object from a database subscription.
  """
  def as_stripe_subscription(subscription) do
    case Stripe.Subscription.retrieve(subscription.stripe_id) do
      {:ok, result} -> result
      _ -> nil
    end
  end

  @doc """
  Increments the quantity of a subscription item. Defaults to incrementing the first item. Defaults to incrementing by one.

  ## Examples
      # this would update the first subscription item's quantity by one
      # useful for single price subscriptions
      subscription = increment(subscription)

      # you can also specify a price and quantity to increment by
      subscription = increment(subscription, price_id: "price_123", quantity: 2)

      # can pass any valid Stripe.SubscriptionItem.update/2 params
      subscription = increment(subscription, stripe: %{ prorate: false })
  """
  def increment(subscription, opts \\ []) do
    quantity = Keyword.get(opts, :quantity, 1)
    price_id = Keyword.get(opts, :price_id, nil)

    item =
      subscription_items(subscription)
      |> Enum.find(fn x ->
        if !price_id, do: true, else: x.stripe_price_id == price_id
      end)

    cond do
      quantity < 1 ->
        raise "You must increment by at least 1"

      has_multiple_prices?(subscription) && price_id == nil ->
        raise "You must specify a price_id when incrementing a subscription with multiple prices"

      true ->
        new_opts =
          Keyword.merge(opts, quantity: item.quantity + quantity, price_id: item.stripe_price_id)

        set_quantity(subscription, new_opts)
    end
  end

  @doc """
   Decrements the quantity of a subscription item. Defaults to decrementing the first item. Defaults to decrementing by one. Raises if trying to go below 0.

   ## Examples
        # this would update the first subscription item's quantity by one
        # useful for single price subscriptions
        subscription = decrement(subscription)

        # you can also specify a price and quantity to decrement by
        subscription = decrement(subscription, price_id: "price_123", quantity: 2)

        # can pass any valid Stripe.SubscriptionItem.update/2 params
        subscription = decrement(subscription, stripe: %{ prorate: false })
  """
  def decrement(subscription, opts \\ []) do
    quantity = Keyword.get(opts, :quantity, 1)
    price_id = Keyword.get(opts, :price_id, nil)

    item =
      subscription_items(subscription)
      |> Enum.find(fn x ->
        if !price_id, do: true, else: x.stripe_price_id == price_id
      end)

    new_quantity = item.quantity - quantity

    cond do
      quantity < 1 ->
        raise "You cannot decrement a subscription quantity by less than 1"

      has_multiple_prices?(subscription) && price_id == nil ->
        raise "You must specify a price_id when incrementing a subscription with multiple prices"

      new_quantity <= 0 ->
        raise "You cannot decrement a subscription quantity to less than 0"

      true ->
        new_opts = Keyword.merge(opts, quantity: new_quantity, price_id: item.stripe_price_id)
        set_quantity(subscription, new_opts)
    end
  end

  @doc """
  Sets the quantity of a subscription item. Defaults to setting the first item. Defaults to setting to one.

  ## Examples
      # this would update the first subscription item's quantity to one
      # useful for single price subscriptions
      subscription = set_quantity(subscription)

      # you can also specify a price and quantity to set to
      subscription = set_quantity(subscription, price_id: "price_123", quantity: 2)

      # can pass any valid Stripe.SubscriptionItem.update/2 params
      subscription = set_quantity(subscription, stripe: %{ prorate: false })
  """
  def set_quantity(subscription, opts \\ []) do
    quantity = Keyword.get(opts, :quantity, 1)
    price_id = Keyword.get(opts, :price_id, nil)
    stripe_params = stripe_params(opts)
    repo = Bling.repo()

    item =
      subscription_items(subscription)
      |> Enum.find(fn x ->
        if !price_id, do: true, else: x.stripe_price_id == price_id
      end)

    cond do
      quantity < 1 ->
        raise "You must set a subscription quantity to at least 1"

      has_multiple_prices?(subscription) && price_id == nil ->
        raise ArgumentError,
              "You must specify a price_id when changing quantity of a subscription with multiple prices"

      true ->
        params = Map.merge(stripe_params, %{quantity: quantity})
        Stripe.SubscriptionItem.update(item.stripe_id, params)
        stripe_subscription = as_stripe_subscription(subscription)

        item |> change(%{quantity: quantity}) |> repo.update!()

        subscription
        |> change(%{
          stripe_status: stripe_subscription.status
        })
        |> repo.update!()

        reload_with_items(subscription)
    end
  end

  @doc """
  Turns a stripe subscription object into a database subscription without committing it. Meant for internal use.

  ## Examples
      subscription =
        subscription_struct_from_stripe_subscription(MyApp.Subscriptions.Subscription, stripe_subscription)
        |> MyApp.Repo.insert()
  """
  def subscription_struct_from_stripe_subscription(
        schema_or_subscription,
        %Stripe.Subscription{} = event
      ) do
    trial_end =
      if event.trial_end do
        event.trial_end |> DateTime.from_unix!() |> DateTime.truncate(:second)
      else
        nil
      end

    ends_at =
      cond do
        event.cancel_at_period_end ->
          if trial_end,
            do: trial_end,
            else: event.current_period_end |> DateTime.from_unix!() |> DateTime.truncate(:second)

        event.cancel_at ->
          event.cancel_at |> DateTime.from_unix!() |> DateTime.truncate(:second)

        true ->
          nil
      end

    name =
      cond do
        Map.has_key?(event, :metadata) and not is_nil(Map.get(event.metadata, "name")) ->
          Map.get(event.metadata, "name", @default_plan)

        is_struct(schema_or_subscription) ->
          schema_or_subscription.name || @default_plan

        true ->
          @default_plan
      end

    schema_or_subscription
    |> struct()
    |> Ecto.Changeset.change(%{
      name: name,
      stripe_id: event.id,
      stripe_status: event.status,
      trial_ends_at: trial_end,
      ends_at: ends_at
    })
  end

  @doc """
  Turns an array of stripe subscription items into database subscription structs. Meant for internal use.

  ## Examples
      subscription =
        subscription_struct_from_stripe_subscription(MyApp.Subscriptions.Subscription, stripe_subscription)
        |> MyApp.Repo.insert()

      subscription_items =
        subscription_item_structs_from_stripe_items(stripe_subscription.items.data, subscription)
        |> Enum.each(&MyApp.Repo.insert/1)
  """
  def subscription_item_structs_from_stripe_items(items, db_subscription) do
    items
    |> Enum.map(fn sub_item ->
      Ecto.build_assoc(db_subscription, :subscription_items, %{
        stripe_id: sub_item.id,
        stripe_product_id: sub_item.price.product,
        stripe_price_id: sub_item.price.id,
        quantity: sub_item.quantity
      })
    end)
  end

  defp build_opts(opts, defaults \\ %{}) do
    opts = opts |> Enum.into(%{})

    Map.merge(defaults, opts)
  end

  defp stripe_params(opts), do: opts |> Keyword.get(:stripe, []) |> build_opts()

  defp reload_with_items(subscription) do
    repo = Bling.repo()

    subscription |> repo.reload() |> repo.preload(:subscription_items)
  end
end
