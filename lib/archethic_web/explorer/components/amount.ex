defmodule ArchethicWeb.Explorer.Components.Amount do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.WebUtils

  @max_symbol_len 6

  def uco(assigns = %{amount: 0}) do
    ~H"""
    <span class="mono" data-tooltip="at time: 0$, now: 0$">
      0 <span class="tag is-gradient mono">UCO</span>
    </span>
    """
  end

  def uco(assigns) do
    assigns =
      assign(
        assigns,
        %{
          amount: from_bigint(assigns.amount),
          tooltip:
            case Map.get(assigns, :uco_price_at_time) do
              nil ->
                "now: " <>
                  format_usd_amount(
                    assigns.amount,
                    assigns.uco_price_now[:usd]
                  )

              _ ->
                format_full_usd_amount(
                  assigns.amount,
                  assigns.uco_price_at_time[:usd],
                  assigns.uco_price_now[:usd]
                )
            end
        }
      )

    ~H"""
    <span class="mono" data-tooltip={@tooltip}>
      <%= @amount %> <span class="tag is-gradient mono">UCO</span>
    </span>
    """
  end

  def token(assigns) do
    decimals =
      Map.get(assigns.token_properties, assigns.token_address, %{}) |> Map.get(:decimals, 8)

    assigns =
      assign(assigns, %{
        amount: from_bigint(assigns.amount, decimals),
        token_name:
          if assigns.token_id > 0 do
            "NFT ##{assigns.token_id}"
          else
            case Map.get(assigns.token_properties, assigns.token_address, %{})
                 |> Map.get(:symbol) do
              nil ->
                short_address(assigns.token_address)

              symbol ->
                if String.length(symbol) > @max_symbol_len do
                  content_tag(
                    "span",
                    String.slice(symbol, 0..(@max_symbol_len - 1)) <> "...",
                    "data-tooltip":
                      symbol <> " minted at " <> Base.encode16(assigns.token_address),
                    class: "mono"
                  )
                else
                  content_tag(
                    "span",
                    symbol,
                    "data-tooltip":
                      symbol <> " minted at " <> Base.encode16(assigns.token_address),
                    class: "mono"
                  )
                end
            end
          end
      })

    ~H"""
    <span class="mono">
      <%= @amount %>

      <%= link(      to:
          Routes.live_path(
            @socket,
            ArchethicWeb.Explorer.TransactionDetailsLive,
            Base.encode16(@token_address)
          )
      ) do %>
        <span class="tag is-gradient mono"><%= @token_name %></span>
      <% end %>
    </span>
    """
  end
end