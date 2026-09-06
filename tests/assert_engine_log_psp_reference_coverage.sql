select
  txn_id,
  psp,
  psp_reference
from {{ ref('stg__payment_engine_log') }}
where (psp = 'google_play' and psp_reference is not null)
   or (psp <> 'google_play' and psp_reference is null)
