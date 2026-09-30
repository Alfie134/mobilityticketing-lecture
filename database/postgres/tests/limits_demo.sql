-- limits_demo.sql
-- Evidence for the rules the integrity migration does NOT protect (L1-L6 in
-- docs/lecture-2/integrity-map.md). Each block makes a write that is ACCEPTED
-- today, shows the resulting inconsistent state, and rolls it back.
--
-- Run after applying the migration:
--   docker compose exec -T postgres psql -U mobility -d mobility \
--       < database/postgres/tests/limits_demo.sql
--
-- This file is a demonstration of gaps, not a test suite: when a later lecture
-- closes one of these gaps, the matching block should start failing.

\echo === L1: history can be rewritten: payment amount and ticket price edited after capture
begin;
update payments set amount = 1 where id = 'PAYMENT-1';
update tickets  set price  = 0 where id = 'TICKET-1';
select p.amount as payment_amount, t.price as ticket_price
from payments p join tickets t on t.id = p.ticket_id where p.id = 'PAYMENT-1';
rollback;

\echo === L2: payment amount/currency unrelated to ticket; payer is not the ticket owner
begin;
insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
values ('PAY-LIE', 'USER-2', 'TICKET-1', 'gateway-lie', 1, 'EUR', 'Captured');
select p.id, p.user_id as payer, k.user_id as owner, p.amount, p.currency as pay_cur,
        k.price, k.currency as tkt_cur
from payments p join tickets k on k.id = p.ticket_id where p.id = 'PAY-LIE';
rollback;

\echo === L3: ticket sold for a cancelled trip to a disabled user
begin;
update trips set status = 'Cancelled' where id = 'TRIP-M2-20260429-1200';
update users set is_disabled = true where id = 'USER-2';
insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
values ('T-BAD-SALE', 'USER-2', 'TRIP-M2-20260429-1200', 'CODE-BAD-SALE', 'Active', 'SINGLE',
        '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36, 'DKK');
select k.id, t.status as trip_status, u.is_disabled
from tickets k join trips t on t.id = k.trip_id join users u on u.id = k.user_id
where k.id = 'T-BAD-SALE';
rollback;

\echo === L4: accepted validation outside the validity window, with no stop, vehicle or device
begin;
insert into validations (id, ticket_id, ticket_code, result, validated_utc)
values ('VAL-LATE', 'TICKET-1', 'CODE-M2-0001', 'Accepted', '2027-01-01 00:00:00+00');
select v.id, v.result, v.validated_utc, t.valid_to_utc, v.stop_id, v.vehicle_id, v.device_id
from validations v join tickets t on t.id = v.ticket_id where v.id = 'VAL-LATE';
rollback;

\echo === L5: same ticket accepted twice; ticket still Active
begin;
insert into validations (id, ticket_id, ticket_code, result)
values ('VAL-A', 'TICKET-1', 'CODE-M2-0001', 'Accepted'),
        ('VAL-B', 'TICKET-1', 'CODE-M2-0001', 'Accepted');
select t.status as ticket_status, count(*) as accepted_validations
from validations v join tickets t on t.id = v.ticket_id
where v.ticket_id = 'TICKET-1' and v.result = 'Accepted' group by t.status;
rollback;

\echo === L6: currency shape is not membership
begin;
update products set currency = 'ZZZ' where code = 'SINGLE';
select code, currency from products where code = 'SINGLE';
rollback;

\echo === L7: the reserved_seats counter is a separate fact from the tickets that exist
select t.id, t.capacity, t.reserved_seats as counter,
        count(k.id) filter (where k.status in ('Pending', 'Active', 'Validated')) as live_tickets
from trips t left join tickets k on k.trip_id = t.id
group by t.id, t.capacity, t.reserved_seats
order by t.id;
