defmodule Bling.Paddle do
  defmacro __using__(_opts) do
    quote do
    end
  end

  def script_tags() do
    vendor_id = Application.get_env(:bling, :paddle)[:vendor_id]
    sandbox? = Application.get_env(:bling, :paddle)[:sandbox] || false
    sandbox_str = if sandbox?, do: "Paddle.Environment.set('sandbox');", else: ""

    Phoenix.HTML.raw("""
    <script src="https://cdn.paddle.com/paddle/paddle.js"></script>
    <script type="text/javascript">
      #{sandbox_str}

      Paddle.Setup({ vendor: #{vendor_id} });
    </script>
    """)
  end

  def deactivate_past_due?() do
    opts = Application.get_env(:bling, :paddle, [])
    val = Keyword.get(opts, :deactivate_past_due?, true)

    val == true
  end
end
