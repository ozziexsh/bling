defmodule Bling.Stripe.Router do
  @moduledoc """
  Provides a macro to register the routes for Bling.
  """

  @doc """
  Registers the routes for Bling. Defaults to a prefix of "/billing".

  These routes are protected by the `Bling.can_manage_billing?` method of your `MyApp.Bling` module.

  The following routes are registered:
  - GET /billing/:customer_type/:customer_id/finalize
    - this is used to resolve payment issues, can be used as a stripe redirect or directly with a query string of `?payment_intent=pi_xxx` or `?setup_intent=si_xxx`
  - POST /billing/:customer_type/:customer_id/payment-method
    - this is used by the finalize route to update the customers payment method if required
  """
  defmacro bling_routes(prefix \\ "/billing") do
    quote do
      pipeline :bling_pipeline do
        plug(:put_root_layout, {Bling.Stripe.Controllers.Layouts, :root})
      end

      scope unquote(prefix), as: false, alias: false do
        scope "/:customer_type/:customer_id" do
          pipe_through([:bling_pipeline])

          opts = [
            assigns: %{route_helpers: __MODULE__.Helpers}
          ]

          Phoenix.Router.get(
            "/finalize",
            Bling.Stripe.Controllers.BlingController,
            :finalize,
            Keyword.merge(opts, as: :bling_finalize)
          )

          Phoenix.Router.post(
            "/payment-method",
            Bling.Stripe.Controllers.BlingController,
            :store_payment_method,
            Keyword.merge(opts, as: :bling_store_payment_method)
          )
        end
      end
    end
  end
end
