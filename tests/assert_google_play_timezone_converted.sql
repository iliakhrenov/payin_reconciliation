-- The file states America/Los_Angeles in a preamble we discard. Left unconverted, every sale
-- misses the engine by seven hours and the whole provider reads as unmatched. Asserted against
-- the engine's capture time rather than against the header's claim.
select
  staged.match_key,
  staged.created_at_utc
from {{ ref('stg__payment_log_google_play') }} as staged
left join {{ ref('stg__payment_engine_log') }} as engine
  on engine.psp = 'google_play'
 and engine.captured_at_utc = staged.created_at_utc
 and engine.sku = split_part(staged.match_key, '|', 2)
 and engine.country = split_part(staged.match_key, '|', 3)
 and lower(engine.operation_type) = staged.operation_type
where engine.txn_id is null
