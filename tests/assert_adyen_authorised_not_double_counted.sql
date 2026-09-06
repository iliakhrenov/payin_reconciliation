-- Adyen ships Authorised and Settled per sale. Staging must emit one row; 1,619 settled sales, not 3,238.
with

raw_settled as (
  select count(*) as n
  from {{ source('payin', 'adyen_payment_accounting') }}
  where "Record Type" = 'Settled'
),

staged_settled as (
  select count(*) as n
  from {{ ref('stg__payment_log_adyen') }}
  where operation_type = 'sale' and status = 'settled'
)

select raw_settled.n as raw_n, staged_settled.n as staged_n
from raw_settled, staged_settled
where raw_settled.n <> staged_settled.n
