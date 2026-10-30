begin;
insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, product_id,
                    valid_from_utc, valid_to_utc, price, currency)
select 'TICKET-MISMATCH', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-MISMATCH', 'Active',
        'SINGLE', p.id, '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36.00, 'DKK'
from products p where p.code = 'DAY';
select t.id, t.product_code, t.product_id, p.code as code_of_that_id
from tickets t join products p on p.id = t.product_id
where t.id = 'TICKET-MISMATCH';
rollback;