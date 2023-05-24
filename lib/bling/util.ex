defmodule Bling.Util do
  @moduledoc false

  @doc """
  Given {module, function, args}, if the function is exported, call it with the arguments.
  If not, return default.
  """
  def maybe_call(mfa, default \\ nil)

  def maybe_call({mod, fun}, default), do: maybe_call({mod, fun, []}, default)

  def maybe_call({mod, fun, args}, default) do
    arity = Enum.count(args)

    if Kernel.function_exported?(mod, fun, arity) do
      apply(mod, fun, args)
    else
      default
    end
  end
end
