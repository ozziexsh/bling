# Upgrading

## 0.1.1 -> 0.2.0

0.2.0 introduced a new field `trial_ends_at` to your customer tables to accomodate generic trials.

1. Create a migration to add this to your customer tables

```elixir
alter table(:users) do
  add :trial_ends_at, :utc_datetime, null: true
end
```

2. Add the field to the ecto schema

```elixir
schema "users" do
  # ...

  field :trial_ends_at, :utc_datetime
end
```
