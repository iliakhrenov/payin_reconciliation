with

src as (
  select * from {{ source('payin', 'payment_engine_log') }}
),

final as (
  select
    txn_id,
    order_id,
    lower(operation_type) as operation_type,
    lower(status) as status,
    psp,
    psp_reference,
    sku,
    country,
    currency,
    cast(amount_local as decimal(18, 2)) as amount_local,
    cast(fx_rate_applied as decimal(18, 6)) as fx_rate_applied,
    cast(fx_date_applied as date) as fx_date_applied,
    cast(amount_usd as decimal(18, 2)) as amount_usd,
    cast(created_at_utc as timestamp) as created_at_utc,
    cast(captured_at_utc as timestamp) as captured_at_utc
  from src
)

select * from final
