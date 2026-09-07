-- The waterfall is derived from the summary mart, two steps removed from the transaction data.
-- This ties its three anchor levels straight back to the classified rows, so a fault in the
-- derivation cannot reach the CFO summary looking plausible.
with

waterfall as (
  select
    psp,
    max(usd) filter (where line_item = 'backend_booked') as booked_usd,
    max(usd) filter (where line_item = 'provider_gross') as gross_usd,
    max(usd) filter (where line_item = 'net_receipts') as net_usd
  from {{ ref('mart__recon_waterfall') }}
  group by 1
),

control as (
  select
    psp,
    sum(engine_amount_usd_booked_period) as booked_usd,
    sum(psp_amount_usd_period) + sum(psp_amount_usd_duplicate_period) as gross_usd,
    sum(psp_amount_usd_period) + sum(psp_amount_usd_duplicate_period)
      - sum(coalesce(psp_fee_usd, 0)) filter (where psp_in_period) as net_usd
  from {{ ref('int__recon_classified') }}
  where in_period
  group by 1
)

select
  w.psp,
  w.booked_usd,
  c.booked_usd as control_booked_usd,
  w.gross_usd,
  c.gross_usd as control_gross_usd,
  w.net_usd,
  c.net_usd as control_net_usd
from waterfall w
join control c on c.psp = w.psp
where abs(w.booked_usd - c.booked_usd) > 0.005
   or abs(w.gross_usd - c.gross_usd) > 0.005
   or abs(w.net_usd - c.net_usd) > 0.005
