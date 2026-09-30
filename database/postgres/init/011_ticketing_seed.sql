insert into trips (
    id, route_id, service_date, scheduled_departure_utc, status,
    capacity, reserved_seats
) values
    ('TRIP-M2-20260429-0800', 'LINE-M2', '2026-04-29', '2026-04-29 08:00:00+00', 'Scheduled', 120, 2),
    ('TRIP-M2-20260429-1200', 'LINE-M2', '2026-04-29', '2026-04-29 12:00:00+00', 'Scheduled', 120, 0),
    ('TRIP-5C-20260429-0900', 'LINE-5C', '2026-04-29', '2026-04-29 09:00:00+00', 'Scheduled', 80, 1),
    ('TRIP-5C-20260429-1700', 'LINE-5C', '2026-04-29', '2026-04-29 17:00:00+00', 'Scheduled', 80, 0)
on conflict do nothing;

insert into products (code, name, price, currency) values
    ('SINGLE', 'Single trip', 36.00, 'DKK'),
    ('DAY', 'Day pass', 80.00, 'DKK')
on conflict do nothing;

insert into users (id, email, full_name, is_disabled) values
    ('USER-1', 'anna@example.test', 'Anna Jensen', false),
    ('USER-2', 'bo@example.test', 'Bo Nielsen', false)
on conflict do nothing;

insert into tickets (
    id, user_id, trip_id, ticket_code, status, product_code,
    valid_from_utc, valid_to_utc, price, currency
) values
    ('TICKET-1', 'USER-1', 'TRIP-M2-20260429-0800', 'CODE-M2-0001', 'Active', 'SINGLE',
        '2026-04-29 07:45:00+00', '2026-04-29 10:00:00+00', 36.00, 'DKK'),
    ('TICKET-2', 'USER-2', 'TRIP-5C-20260429-0900', 'CODE-5C-0001', 'Validated', 'SINGLE',
        '2026-04-29 08:45:00+00', '2026-04-29 11:00:00+00', 36.00, 'DKK')
on conflict do nothing;

insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values
    ('PAYMENT-1', 'USER-1', 'TICKET-1', 'gateway-capture-0001', 36.00, 'DKK', 'Captured', '2026-04-29 07:40:00+00'),
    ('PAYMENT-2', 'USER-2', 'TICKET-2', 'gateway-capture-0002', 36.00, 'DKK', 'Captured', '2026-04-29 08:40:00+00')
on conflict do nothing;

insert into validations (
    id, ticket_id, ticket_code, vehicle_id, stop_id, device_id,
    result, validated_utc
) values
    ('VALIDATION-1', 'TICKET-2', 'CODE-5C-0001', 'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01',
        'Accepted', '2026-04-29 09:10:00+00')
on conflict do nothing;
