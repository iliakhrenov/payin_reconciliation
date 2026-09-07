-- Each subtotal must be the lines above it. A waterfall whose steps do not add up is worse
-- than no waterfall - it reads as arithmetic the reader is not expected to check.
with

w as (
  select
    psp,
    max(usd) filter (where line_item = 'backend_booked') as booked,
    max(usd) filter (where line_item = 'backend_fx_faults') as faults,
    max(usd) filter (where line_item = 'backend_restated') as restated,
    max(usd) filter (where line_item = 'provider_variance') as variance,
    max(usd) filter (where line_item = 'provider_gross') as gross,
    max(usd) filter (where line_item = 'provider_fees') as fees,
    max(usd) filter (where line_item = 'net_receipts') as net
  from {{ ref('mart__recon_waterfall') }}
  group by 1
)

select *
from w
where abs(booked + faults - restated) > 0.005
   or abs(restated + variance - gross) > 0.005
   or abs(gross + fees - net) > 0.005
