with

src as (
  select * from {{ source('payin', 'payment_engine_log') }}
),

final as (
  select * from src
)

select * from final