import Config

config :bling,
  repo: BlingTest.Repo,
  subscription: BlingTest.Subscription,
  subscription_item: BlingTest.SubscriptionItem,
  customers: [user: BlingTest.User],
  bling: BlingTest.ExampleBling

import_config("test.secret.exs")
