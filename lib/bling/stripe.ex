defmodule Bling.Stripe do
  defmacro __using__(_opts \\ []) do
    quote do
      def customer_from_stripe_id(stripe_id) do
        Enum.find_value(customers(), fn {_, schema} ->
          repo().get_by(schema, stripe_id: stripe_id)
        end)
      end
    end
  end
end
