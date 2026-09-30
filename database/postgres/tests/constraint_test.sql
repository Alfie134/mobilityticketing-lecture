-- constraints_test.sql
-- Negative and positive tests for 011_ticketing_integrity.sql.
--
-- Run (after applying the migration):
--   docker compose exec -T postgres psql -U mobility -d mobility \
--       -v ON_ERROR_STOP=1 < database/postgres/tests/constraints_test.sql
--
-- Exit status is non-zero if any test fails, so this can run in CI.
--
-- How it works
--   * expect_failure(name, statement, sqlstate, object) runs the statement and
--     passes only if PostgreSQL rejects it with exactly that SQLSTATE AND the
--     named constraint / column. Checking the object matters: a write rejected
--     by the WRONG rule is a bug, not a pass. Matching English error text is
--     avoided on purpose (language- and version-dependent).
--   * expect_success(name, statement) runs a write that must be accepted.
--   * Every statement runs in its own sub-transaction that is always rolled
--     back, so the suite never changes the seed data and can be re-run freely.
--
-- SQLSTATE reference: 23502 not_null_violation, 23503 foreign_key_violation,
-- 23505 unique_violation, 23514 check_violation.

create temp table test_results (
    n         serial primary key,
    test_name text    not null,
    expected  text    not null,
    actual    text    not null,
    ok        boolean not null
);

create function pg_temp.expect_failure(
    test_name text, stmt text, expected_state text, expected_object text
) returns void language plpgsql as $$
declare
    v_state  text;
    v_constr text;
    v_col    text;
    v_actual text;
    v_ok     boolean;
begin
    begin
        execute stmt;
        raise exception 'write was accepted' using errcode = 'ZZ000';
    exception when others then
        get stacked diagnostics
            v_state  = returned_sqlstate,
            v_constr = constraint_name,
            v_col    = column_name;
    end;

    if v_state = 'ZZ000' then
        v_actual := 'write was accepted';
        v_ok := false;
    else
        v_actual := v_state || ' ' || coalesce(nullif(v_constr, ''), nullif(v_col, ''), '(no object)');
        v_ok := v_state = expected_state
            and coalesce(nullif(v_constr, ''), nullif(v_col, '')) = any (string_to_array(expected_object, '|'));
    end if;

    insert into test_results (test_name, expected, actual, ok)
    values (test_name, expected_state || ' ' || expected_object, v_actual, v_ok);
end $$;

create function pg_temp.expect_success(test_name text, stmt text)
returns void language plpgsql as $$
declare
    v_state text;
    v_msg   text;
    v_ok    boolean := false;
begin
    begin
        execute stmt;
        raise exception 'rollback probe' using errcode = 'ZZ000';
    exception when others then
        get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
        v_ok := (v_state = 'ZZ000');
    end;

    insert into test_results (test_name, expected, actual, ok)
    values (test_name, 'write accepted',
            case when v_ok then 'write accepted' else v_state || ' ' || v_msg end, v_ok);
end $$;

-- Silence the empty result rows of the helper calls; only the report is printed.
\o /dev/null

-- ===========================================================================
-- Writes that MUST be rejected
-- ===========================================================================

-- INV-01 capacity present and non-negative --------------------------------
select pg_temp.expect_failure('F01 INV-01 negative capacity',
$q$ update trips set capacity = -1 where id = 'TRIP-M2-20260429-0800' $q$,
'23514', 'trips_capacity_non_negative');

select pg_temp.expect_failure('F02 INV-01 capacity is required',
$q$ insert into trips (id, route_id, service_date, scheduled_departure_utc, status, capacity, reserved_seats)
    values ('TRIP-NULL-CAP', 'LINE-M2', '2026-04-30', '2026-04-30 08:00:00+00', 'Scheduled', null, 0) $q$,
'23502', 'capacity');

-- INV-02 reserved seats 0..capacity ----------------------------------------
select pg_temp.expect_failure('F03 INV-02 reserved seats above capacity',
$q$ update trips set reserved_seats = capacity + 1 where id = 'TRIP-M2-20260429-0800' $q$,
'23514', 'trips_reserved_seats_valid');

select pg_temp.expect_failure('F04 INV-02 negative reserved seats',
$q$ update trips set reserved_seats = -1 where id = 'TRIP-M2-20260429-0800' $q$,
'23514', 'trips_reserved_seats_valid');

-- INV-03 trip status -------------------------------------------------------
select pg_temp.expect_failure('F05 INV-03 unknown trip status',
$q$ update trips set status = 'Delayed' where id = 'TRIP-M2-20260429-0800' $q$,
'23514', 'trips_status_known');

-- INV-04 money is never negative -------------------------------------------
select pg_temp.expect_failure('F06 INV-04 negative product price',
$q$ update products set price = -1 where code = 'SINGLE' $q$,
'23514', 'products_price_non_negative');

select pg_temp.expect_failure('F07 INV-04 negative ticket price',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-NEG-PRICE', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-NEG-PRICE', 'Active', 'SINGLE',
            '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', -36, 'DKK') $q$,
'23514', 'tickets_price_non_negative');

select pg_temp.expect_failure('F08 INV-04 negative payment amount',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-NEG', 'USER-1', 'TICKET-1', 'gateway-neg', -36, 'DKK', 'Captured') $q$,
'23514', 'payments_amount_non_negative');

-- INV-05 currency present and consistently represented ----------------------
select pg_temp.expect_failure('F09 INV-05 lowercase currency on product',
$q$ update products set currency = 'dkk' where code = 'SINGLE' $q$,
'23514', 'products_currency_iso_shape');

select pg_temp.expect_failure('F10 INV-05 currency is required on ticket',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-NULL-CUR', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-NULL-CUR', 'Active', 'SINGLE',
            '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36, null) $q$,
'23502', 'currency');

select pg_temp.expect_failure('F11 INV-05 two-letter currency on payment',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-BAD-CUR', 'USER-1', 'TICKET-1', 'gateway-bad-cur', 36, 'DK', 'Captured') $q$,
'23514', 'payments_currency_iso_shape');

-- INV-06 status vocabularies -----------------------------------------------
select pg_temp.expect_failure('F12 INV-06 unknown ticket status',
$q$ update tickets set status = 'Unknown' where id = 'TICKET-1' $q$,
'23514', 'tickets_status_known');

select pg_temp.expect_failure('F13 INV-06 unknown payment status',
$q$ update payments set status = 'Settled' where id = 'PAYMENT-1' $q$,
'23514', 'payments_status_known');

select pg_temp.expect_failure('F14 INV-06 unknown validation result',
$q$ update validations set result = 'Maybe' where id = 'VALIDATION-1' $q$,
'23514', 'validations_result_known');

-- INV-07 validity window ---------------------------------------------------
select pg_temp.expect_failure('F15 INV-07 validity ends before it starts',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-REVERSED', 'USER-1', 'TRIP-M2-20260429-0800', 'CODE-REVERSED', 'Active', 'SINGLE',
            '2026-04-29 09:00:00+00', '2026-04-29 08:00:00+00', 36, 'DKK') $q$,
'23514', 'tickets_validity_window_valid');

-- INV-08 ticket code is canonical ------------------------------------------
select pg_temp.expect_failure('F16 INV-08 ticket code with trailing space',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-SPACE', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-SPACE ', 'Active', 'SINGLE',
            '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36, 'DKK') $q$,
'23514', 'tickets_ticket_code_canonical');

select pg_temp.expect_failure('F17 INV-08 empty ticket code',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-EMPTY', 'USER-1', 'TRIP-M2-20260429-1200', '', 'Active', 'SINGLE',
            '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36, 'DKK') $q$,
'23514', 'tickets_ticket_code_canonical');

-- INV-09 captured payment carries a reference --------------------------------
select pg_temp.expect_failure('F18 INV-09 captured payment without gateway reference',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-NO-REF', 'USER-1', 'TICKET-1', null, 36, 'DKK', 'Captured') $q$,
'23514', 'payments_captured_has_reference');

-- INV-10 ticket references user, trip, product -------------------------------
select pg_temp.expect_failure('F19 INV-10 ticket for unknown trip',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-INVALID-TRIP', 'USER-1', 'TRIP-DOES-NOT-EXIST', 'CODE-INVALID-TRIP', 'Active', 'SINGLE',
            '2026-04-29 08:00:00+00', '2026-04-29 09:00:00+00', 36, 'DKK') $q$,
'23503', 'tickets_trip_fk');

select pg_temp.expect_failure('F20 INV-10 ticket for unknown user',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-INVALID-USER', 'NO-SUCH-USER', 'TRIP-M2-20260429-1200', 'CODE-INVALID-USER', 'Active', 'SINGLE',
            '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36, 'DKK') $q$,
'23503', 'tickets_user_fk');

select pg_temp.expect_failure('F21 INV-10 ticket for unknown product',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-INVALID-PROD', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-INVALID-PROD', 'Active', 'NO-SUCH-PRODUCT',
            '2026-04-29 11:00:00+00', '2026-04-29 13:00:00+00', 36, 'DKK') $q$,
'23503', 'tickets_product_fk');

-- INV-11 payment references ticket and user -----------------------------------
select pg_temp.expect_failure('F22 INV-11 payment for unknown ticket',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-UNKNOWN-TICKET', 'USER-1', 'NO-SUCH-TICKET', 'gateway-capture-invalid', 36, 'DKK', 'Captured') $q$,
'23503', 'payments_ticket_fk');

select pg_temp.expect_failure('F23 INV-11 payment by unknown user',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-UNKNOWN-USER', 'NO-SUCH-USER', 'TICKET-1', 'gateway-unknown-user', 36, 'DKK', 'Captured') $q$,
'23503', 'payments_user_fk');

-- INV-12 validation references a real ticket; id and code must belong together -
select pg_temp.expect_failure('F24 INV-12 validation for unknown ticket',
$q$ insert into validations (id, ticket_id, ticket_code, vehicle_id, stop_id, device_id, result)
    values ('VAL-UNKNOWN', 'NO-SUCH-TICKET', 'CODE-NOPE', 'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01', 'Accepted') $q$,
'23503', 'validations_ticket_fk');

select pg_temp.expect_failure('F25 INV-12 id of one ticket with code of another',
$q$ insert into validations (id, ticket_id, ticket_code, vehicle_id, stop_id, device_id, result)
    values ('VALIDATION-MISMATCH', 'TICKET-1', 'CODE-5C-0001', 'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01', 'Accepted') $q$,
'23503', 'validations_ticket_fk');

-- INV-13 validation stop exists ----------------------------------------------
select pg_temp.expect_failure('F26 INV-13 validation at unknown stop',
$q$ insert into validations (id, ticket_id, ticket_code, vehicle_id, stop_id, device_id, result)
    values ('VAL-BAD-STOP', 'TICKET-2', 'CODE-5C-0001', 'BUS-5C-01', 'STOP-NOWHERE', 'DEVICE-01', 'Accepted') $q$,
'23503', 'validations_stop_fk');

-- INV-14 history cannot be orphaned or re-keyed ----------------------------------
select pg_temp.expect_failure('F27 INV-14 delete a ticket that has a payment',
$q$ delete from tickets where id = 'TICKET-1' $q$,
'23503', 'payments_ticket_fk');

select pg_temp.expect_failure('F28 INV-14 delete a user that has tickets and payments',
$q$ delete from users where id = 'USER-1' $q$,
'23503', 'tickets_user_fk|payments_user_fk');

select pg_temp.expect_failure('F29 INV-14 delete a trip that has tickets',
$q$ delete from trips where id = 'TRIP-M2-20260429-0800' $q$,
'23503', 'tickets_trip_fk');

select pg_temp.expect_failure('F30 INV-14 delete a product that has tickets',
$q$ delete from products where code = 'SINGLE' $q$,
'23503', 'tickets_product_fk');

select pg_temp.expect_failure('F31 INV-14 edit the code of an already validated ticket',
$q$ update tickets set ticket_code = 'CODE-5C-CHANGED' where id = 'TICKET-2' $q$,
'23503', 'validations_ticket_fk');

-- INV-15 / 16 / 17 uniqueness -----------------------------------------------------
select pg_temp.expect_failure('F32 INV-15 duplicate ticket code',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    select 'T-DUPLICATE-CODE', user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency
    from tickets where id = 'TICKET-1' $q$,
'23505', 'tickets_ticket_code_unique');

select pg_temp.expect_failure('F33 INV-16 duplicate email differing only by case',
$q$ insert into users (id, email, full_name) values ('USER-3', 'ANNA@example.test', 'Anna Again') $q$,
'23505', 'users_email_lower_unique');

select pg_temp.expect_failure('F34 INV-16 email is required',
$q$ insert into users (id, email, full_name) values ('USER-4', null, 'No Email') $q$,
'23502', 'email');

select pg_temp.expect_failure('F35 INV-17 second captured payment with the same gateway reference',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAYMENT-DUPLICATE-REFERENCE', 'USER-1', 'TICKET-1', 'gateway-capture-0001', 36, 'DKK', 'Captured') $q$,
'23505', 'payments_captured_reference_unique');

-- ===========================================================================
-- Writes that MUST be accepted (the other half of every rule)
-- ===========================================================================

select pg_temp.expect_success('S01 INV-02 boundary: reserved seats equal to capacity',
$q$ update trips set reserved_seats = capacity where id = 'TRIP-M2-20260429-0800' $q$);

select pg_temp.expect_success('S02 INV-04 boundary: free product (price 0)',
$q$ update products set price = 0 where code = 'DAY' $q$);

select pg_temp.expect_success('S03 INV-07 boundary: validity window of zero length',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-ZERO-WINDOW', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-ZERO-WINDOW', 'Pending', 'SINGLE',
            '2026-04-29 11:00:00+00', '2026-04-29 11:00:00+00', 36, 'DKK') $q$);

select pg_temp.expect_success('S04 INV-10/15 a fully valid ticket',
$q$ insert into tickets (id, user_id, trip_id, ticket_code, status, product_code, valid_from_utc, valid_to_utc, price, currency)
    values ('T-OK', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-OK-0001', 'Active', 'SINGLE',
            '2026-04-29 11:45:00+00', '2026-04-29 14:00:00+00', 36, 'DKK') $q$);

select pg_temp.expect_success('S05 INV-09 a pending payment may exist before the gateway answers',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-PENDING', 'USER-1', 'TICKET-1', null, 36, 'DKK', 'Pending') $q$);

select pg_temp.expect_success('S06 INV-17 a failed payment may reuse a captured reference (only Captured competes)',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-FAILED-SAME-REF', 'USER-1', 'TICKET-1', 'gateway-capture-0001', 36, 'DKK', 'Failed') $q$);

select pg_temp.expect_success('S07 INV-11 a fully valid captured payment',
$q$ insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status)
    values ('PAY-OK', 'USER-1', 'TICKET-1', 'gateway-capture-9001', 36, 'DKK', 'Captured') $q$);

select pg_temp.expect_success('S08 INV-12 a validation whose ticket id and code belong together',
$q$ insert into validations (id, ticket_id, ticket_code, vehicle_id, stop_id, device_id, result)
    values ('VAL-OK', 'TICKET-2', 'CODE-5C-0001', 'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01', 'Accepted') $q$);

select pg_temp.expect_success('S09 INV-16 a genuinely different email',
$q$ insert into users (id, email, full_name) values ('USER-5', 'carl@example.test', 'Carl Hansen') $q$);

select pg_temp.expect_success('S10 INV-01 boundary: a trip may have zero capacity',
$q$ update trips set capacity = 0, reserved_seats = 0 where id = 'TRIP-M2-20260429-1200' $q$);

select pg_temp.expect_success('S11 INV-03 a trip can be retired by status instead of deletion',
$q$ update trips set status = 'Cancelled' where id = 'TRIP-M2-20260429-0800' $q$);

select pg_temp.expect_success('S12 INV-14 RESTRICT only bites when history exists: a trip with no tickets can be deleted',
$q$ delete from trips where id = 'TRIP-5C-20260429-1700' $q$);

-- ===========================================================================
-- Report
-- ===========================================================================
\o
select n as "#", test_name, expected, actual, case when ok then 'PASS' else 'FAIL' end as result
from test_results
order by n;

select count(*) filter (where ok)     as passed,
        count(*) filter (where not ok) as failed,
        count(*)                       as total
from test_results;

do $$
declare v_failed int;
begin
    select count(*) into v_failed from test_results where not ok;
    if v_failed > 0 then
        raise exception '% test(s) failed', v_failed;
    end if;
end $$;
