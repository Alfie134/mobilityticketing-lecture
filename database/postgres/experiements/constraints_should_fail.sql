-- Run each statement separately after applying your integrity migration.
-- Every statement below should be rejected by a named constraint.

-- 1. Negative capacity. Expected: CHECK violation.
update trips
set capacity = -1
where id = 'TRIP-M2-20260429-0800';

-- 2. More reserved seats than capacity. Expected: CHECK violation.
update trips
set reserved_seats = capacity + 1
where id = 'TRIP-M2-20260429-0800';

-- 3. Unknown trip. Expected: FOREIGN KEY violation.
insert into tickets (
    id, user_id, trip_id, ticket_code, status,
    product_code, valid_from_utc, valid_to_utc, price, currency
) values (
    'T-INVALID-TRIP', 'USER-1', 'TRIP-DOES-NOT-EXIST',
    'CODE-INVALID-TRIP', 'Active', 'SINGLE',
    '2026-04-29 08:00:00+00', '2026-04-29 09:00:00+00', 36, 'DKK'
);

-- 4. Reversed validity window. Expected: CHECK violation.
insert into tickets (
    id, user_id, trip_id, ticket_code, status,
    product_code, valid_from_utc, valid_to_utc, price, currency
) values (
    'T-REVERSED', 'USER-1', 'TRIP-M2-20260429-0800',
    'CODE-REVERSED', 'Active', 'SINGLE',
    '2026-04-29 09:00:00+00', '2026-04-29 08:00:00+00', 36, 'DKK'
);

-- 5. Duplicate ticket code. Expected: UNIQUE violation.
insert into tickets (
    id, user_id, trip_id, ticket_code, status,
    product_code, valid_from_utc, valid_to_utc, price, currency
)
select
    'T-DUPLICATE-CODE', user_id, trip_id, ticket_code, status,
    product_code, valid_from_utc, valid_to_utc, price, currency
from tickets
where id = 'TICKET-1';

-- 6. Unknown ticket status. Expected: CHECK violation.
update tickets
set status = 'Unknown'
where id = 'TICKET-1';

-- 7. Negative product price. Expected: CHECK violation.
update products
set price = -1
where code = 'SINGLE';

-- 8. Payment for an unknown ticket. Expected: FOREIGN KEY violation.
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status
) values (
    'PAYMENT-UNKNOWN-TICKET', 'USER-1', 'NO-SUCH-TICKET',
    'gateway-capture-invalid', 36, 'DKK', 'Captured'
);

-- 9. Duplicate external payment reference. Expected: UNIQUE violation.
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status
) values (
    'PAYMENT-DUPLICATE-REFERENCE', 'USER-1', 'TICKET-1',
    'gateway-capture-0001', 36, 'DKK', 'Captured'
);

-- 10. Mismatched ticket id and ticket code. Expected: composite FOREIGN KEY violation.
insert into validations (
    id, ticket_id, ticket_code, vehicle_id, stop_id, device_id, result
) values (
    'VALIDATION-MISMATCH', 'TICKET-1', 'CODE-5C-0001',
    'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01', 'Accepted'
);
