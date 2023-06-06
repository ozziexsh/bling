defmodule Bling.Paddle.Api do
  def vendors_url() do
    sandbox? = Application.get_env(:bling, :paddle)[:sandbox] == true
    subdomain = if sandbox?, do: "sandbox-vendors", else: "vendors"
    "https://#{subdomain}.paddle.com/api/2.0"
  end

  def checkout_url() do
    sandbox? = Application.get_env(:bling, :paddle)[:sandbox] == true
    subdomain = if sandbox?, do: "sandbox-checkout", else: "checkout"
    "https://#{subdomain}.paddle.com/api/2.0"
  end

  def get_auth() do
    %{
      vendor_id: Application.get_env(:bling, :paddle)[:vendor_id],
      vendor_auth_code: Application.get_env(:bling, :paddle)[:vendor_auth_code]
    }
  end

  def subscription_plans(params \\ %{}) do
    url = "#{vendors_url()}/subscription/plans"

    post(url, params)
  end

  def generate_pay_link(params) do
    url = "#{vendors_url()}/product/generate_pay_link"

    post(url, params)
  end

  def subscription_users(params) do
    url = "#{vendors_url()}/subscription/users"

    post(url, params)
  end

  def update_subscription_user(params) do
    url = "#{vendors_url()}/subscription/users/update"

    post(url, params)
  end

  def charge_subscription(subscription, params) do
    url = "#{vendors_url()}/subscription/#{subscription.paddle_id}/charge"

    post(url, params)
  end

  def cancel_subscription(params) do
    url = "#{vendors_url()}/subscription/users_cancel"

    post(url, params)
  end

  defp post(url, params) do
    body = Map.merge(get_auth(), params)

    case HTTPoison.post(url, Jason.encode!(body), [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{} = response} ->
        response.body |> Jason.decode!() |> IO.inspect() |> Map.get("response")

      {:error, error} ->
        IO.inspect(error)
        nil
    end
  end
end
