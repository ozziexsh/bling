defmodule Bling do
  @moduledoc """
  The main Bling module that is installed into your application.

  Auto generated from `mix bling.install`.

      defmodule MyApp.Bling do
        use Bling,
          repo: MyApp.Repo,
          customers: [
            user: MyApp.Accounts.User
          ],
          subscription: MyApp.Subscriptions.Subscription,
          subscription_item: MyApp.Subscriptions.SubscriptionItem
      end

  Provides a few helper functions for deriving information for customer structs.

  Given a module of:

      defmodule MyApp.Bling do
        use Bling,
          customers: [user: MyApp.Accounts.User, team: MyApp.Accounts.Team]
      end

  The following would be returned:

      MyApp.Accounts.User = MyApp.Bling.module_from_customer_type("user")
      MyApp.Accounts.Team = MyApp.Bling.module_from_customer_type("team")
      "user" = MyApp.Bling.customer_type_from_struct(%MyApp.Accounts.User{})
      "team" = MyApp.Bling.customer_type_from_struct(%MyApp.Accounts.Team{})

      # queries the registered customer modules for a matching stripe_id
      %MyApp.Accounts.User{} = MyApp.Bling.customer_from_stripe_id("cus_1234")
  """

  defmacro __using__(opts) do
    opts = Keyword.put(opts, :caller, __CALLER__.module)

    quote do
      @customers unquote(opts[:customers])
      @repo unquote(opts[:repo])
      @subscription unquote(opts[:subscription])
      @subscription_item unquote(opts[:subscription_item])
      @receipt unquote(opts[:receipt])

      def customers, do: @customers
      def repo, do: @repo
      def subscription, do: @subscription
      def subscription_item, do: @subscription_item
      def receipt, do: @receipt

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

      for entity <-
            [@subscription, @subscription_item, @receipt | Keyword.values(@customers)]
            |> Enum.filter(fn x -> not is_nil(x) end) do
        defimpl Bling.Entity, for: entity do
          def repo(_entity), do: unquote(opts[:repo])
          def bling(_entity), do: unquote(opts[:caller])
        end
      end
    end
  end
end
