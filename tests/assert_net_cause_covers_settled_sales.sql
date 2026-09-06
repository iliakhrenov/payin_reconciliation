-- Every settled provider sale carries a fee verdict, even if that verdict is "no contract on file".
-- Anything else - a reversal, a decline, a row the provider never reported - carries none.
select
  psp,
  order_ref,
  operation_type,
  psp_status,
  net_cause
from {{ ref('int__recon_classified') }}
where (in_psp and operation_type = 'sale' and psp_status = 'settled') <> (net_cause is not null)
