insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, product_id,
                    valid_from_utc, valid_to_utc, price, currency)
select 'TICKET-NEW-' || left(gen_random_uuid()::text, 8),
        'USER-2', 'TRIP-5C-20260429-1700',
        'CODE-NEW-' || left(gen_random_uuid()::text, 8),
        'Active', p.code, p.id,
        '2026-04-29 16:00:00+00', '2026-04-29 18:00:00+00', p.price, p.currency
from products p
where p.id = :'product_id'::uuid;