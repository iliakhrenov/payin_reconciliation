with

src as (
  select * from {{ source('payin', 'fee_schedule') }}
),

final as (
  select
    psp,
    account as psp_account,
    cast(valid_from as date) as valid_from,
    cast(percent_fee as decimal(9, 4)) as percent_fee,
    cast(fixed_fee as decimal(18, 2)) as fixed_fee,
    nullif(fixed_fee_currency, '') as fixed_fee_currency
  from src
)

select * from final
