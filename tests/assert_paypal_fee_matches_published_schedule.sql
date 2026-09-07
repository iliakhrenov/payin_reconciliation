-- PayPal is not in fee_schedule, so its reported fee is what the reconciliation books. That is
-- only defensible while the fee is a formula rather than a number the provider chose: percentage
-- plus a fixed fee in the transaction currency, exact to the cent on every settled sale.
select
  psp,
  order_ref,
  currency,
  amount_local_settled,
  fee_local
from {{ ref('stg__payment_log_paypal') }}
where operation_type = 'sale'
  and status = 'settled'
  and fee_local <> round(
        amount_local_settled * case currency when 'USD' then 0.0349 else 0.029 end, 2
      ) + case currency when 'USD' then 0.49 when 'EUR' then 0.35 when 'GBP' then 0.30 end
