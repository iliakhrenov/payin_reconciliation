select
  txn_id,
  status,
  captured_at_utc
from {{ ref('stg__payment_engine_log') }}
where (status = 'settled' and captured_at_utc is null)
   or (status in ('declined', 'pending') and captured_at_utc is not null)
   or (captured_at_utc < created_at_utc)
