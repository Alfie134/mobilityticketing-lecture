-- Run this script after applying all four reporting mechanisms.
-- Start from a clean container when repeating the complete sequence.

set timezone = 'UTC';

-- Capture the baseline result before changing source data.
select
    'baseline' as case_name,
    r.operator_id,
    p.created_utc::date as revenue_date,
    sum(p.amount) as captured_amount,
    count(*) as captured_payments
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date
order by r.operator_id, p.created_utc::date;

-- 1. Captured payment insert. Compare all four approaches.
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-CAPTURED', 'USER-1', 'TICKET-1', 'gateway-case-captured',
    36, 'DKK', 'Captured', '2026-04-29 10:00:00+00'
);

-- 2. Failed payment insert. It should not contribute to captured revenue.
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-FAILED', 'USER-1', 'TICKET-1', 'gateway-case-failed',
    50, 'DKK', 'Failed', '2026-04-29 10:05:00+00'
);

-- 3. Status correction from Failed to Captured.
update payments
set status = 'Captured'
where id = 'PAY-CASE-FAILED';

-- 4. Status correction from Captured to Refunded.
update payments
set status = 'Refunded'
where id = 'PAY-CASE-CAPTURED';

-- 5. Delete or replace test data.
delete from payments
where id = 'PAY-CASE-FAILED';

-- 6. Duplicate delivery of an external payment reference.
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-DUPLICATE', 'USER-1', 'TICKET-1', 'gateway-capture-0001',
    36, 'DKK', 'Captured', '2026-04-29 10:10:00+00'
);

-- Refresh only after observing staleness.
-- refresh materialized view daily_captured_revenue;
