-- A non-zero fixed fee quoted in a currency other than the transaction's would need converting
-- before it can be compared. No contract does that today; fail loudly if one starts.
select
  psp,
  order_ref,
  psp_currency,
  fixed_fee,
  fixed_fee_currency
from {{ ref('int__recon_classified') }}
where fixed_fee <> 0
  and fixed_fee_currency is not null
  and fixed_fee_currency <> psp_currency
