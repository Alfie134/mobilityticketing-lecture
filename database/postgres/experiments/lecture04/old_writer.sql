insert into tickets (id, user_id, trip_id, ticket_code, status, product_code,
                    valid_from_utc, valid_to_utc, price, currency)
values ('TICKET-OLD-' || left(gen_random_uuid()::text, 8),
        'USER-1', 'TRIP-M2-20260429-1200',
        'CODE-OLD-' || left(gen_random_uuid()::text, 8),
        'Active', 'SINGLE',
        '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36.00, 'DKK');