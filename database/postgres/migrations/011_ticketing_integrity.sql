-- 011_ticketing_integrity.sql
-- Lecture 2: make invalid ticketing states difficult to store.
--
-- Applies on top of init/010_ticketing_draft.sql without editing it.
-- Runs in one transaction (PostgreSQL DDL is transactional): either every
-- rule below is in place, or none is. Every constraint is named so that tests
-- and later migrations can identify it (see tests/constraints_test.sql).
--
-- Invariant ids (INV-nn) refer to docs/lecture-2/lab.md.

begin;

-- ---------------------------------------------------------------------------
-- trips: capacity and seat counters (INV-01, INV-02, INV-03)
-- ---------------------------------------------------------------------------
-- These protect ONE row. They cannot stop two concurrent purchases from both
-- reading the same remaining capacity: that race is left for the transactions
-- lecture (INV-18).
alter table trips
    alter column capacity set not null,
    alter column reserved_seats set not null,
    add constraint trips_capacity_non_negative
        check (capacity >= 0),
    add constraint trips_reserved_seats_valid
        check (reserved_seats between 0 and capacity),
    add constraint trips_status_known
        check (status in ('Scheduled', 'Cancelled', 'Completed'));

-- ---------------------------------------------------------------------------
-- products (INV-04, INV-05)
-- ---------------------------------------------------------------------------
-- Currency is stored as an ISO 4217 *shaped* code: exactly three uppercase
-- letters. 'dkk', 'DK' and 'D1K' are rejected, so a report that groups by
-- currency cannot split DKK into several buckets. Shape is not membership:
-- 'ZZZ' still passes (would need a currency lookup table, see INV-27).
alter table products
    alter column name set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint products_price_non_negative
        check (price >= 0),
    add constraint products_currency_iso_shape
        check (currency ~ '^[A-Z]{3}$');

-- ---------------------------------------------------------------------------
-- users (INV-16)
-- ---------------------------------------------------------------------------
-- Uniqueness is on lower(email): 'Anna@x.test' and 'anna@x.test' are the same
-- mailbox for every practical purpose, and a plain UNIQUE (email) would let
-- both in and make login lookup ambiguous.
alter table users
    alter column email set not null,
    alter column is_disabled set not null;

create unique index users_email_lower_unique
    on users (lower(email));

-- ---------------------------------------------------------------------------
-- tickets (INV-04..08, INV-10, INV-14, INV-15)
-- ---------------------------------------------------------------------------
-- Foreign keys use ON DELETE / ON UPDATE RESTRICT explicitly. Tickets,
-- payments and validations are compliance history (brief: "long-term storage
-- for reporting and compliance"), so a parent row that has history cannot be
-- deleted or re-keyed out from under it. Retiring things is done with state:
-- users.is_disabled, trips.status = 'Cancelled'.
--
-- tickets.price / currency are deliberately a snapshot of what the customer
-- was charged, not a reference to products.price, so a later price change
-- does not rewrite old tickets. The consequence (nothing ties the snapshot to
-- the product price at purchase time) is INV-23.
alter table tickets
    alter column user_id set not null,
    alter column trip_id set not null,
    alter column ticket_code set not null,
    alter column status set not null,
    alter column product_code set not null,
    alter column valid_from_utc set not null,
    alter column valid_to_utc set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint tickets_user_fk
        foreign key (user_id) references users (id)
        on delete restrict on update restrict,
    add constraint tickets_trip_fk
        foreign key (trip_id) references trips (id)
        on delete restrict on update restrict,
    add constraint tickets_product_fk
        foreign key (product_code) references products (code)
        on delete restrict on update restrict,
    -- Scanners and customers look tickets up by code, so a code must map to at
    -- most one ticket...
    add constraint tickets_ticket_code_unique
        unique (ticket_code),
    -- ...and must be canonical: ' CODE-1' and 'CODE-1' look identical on a
    -- screen but would be two different, individually "unique" codes.
    add constraint tickets_ticket_code_canonical
        check (ticket_code <> '' and ticket_code = btrim(ticket_code)),
    add constraint tickets_status_known
        check (status in ('Pending', 'Active', 'Validated', 'Cancelled', 'Expired')),
    add constraint tickets_price_non_negative
        check (price >= 0),
    add constraint tickets_currency_iso_shape
        check (currency ~ '^[A-Z]{3}$'),
    -- "End cannot be earlier than start": equal is allowed by the brief.
    add constraint tickets_validity_window_valid
        check (valid_to_utc >= valid_from_utc),
    -- Redundant as a uniqueness rule (id is already the primary key) but it is
    -- the target the composite foreign key on validations needs.
    add constraint tickets_id_code_unique
        unique (id, ticket_code);

-- ---------------------------------------------------------------------------
-- payments (INV-04..06, INV-09, INV-11, INV-14, INV-17)
-- ---------------------------------------------------------------------------
-- external_payment_reference stays nullable: a 'Pending' payment row can be
-- created before the gateway has answered, so it has no reference yet.
-- What is enforced instead is that a *captured* payment always has one, and
-- that one gateway capture cannot be recorded twice.
alter table payments
    alter column user_id set not null,
    alter column ticket_id set not null,
    alter column amount set not null,
    alter column currency set not null,
    alter column status set not null,
    alter column created_utc set not null,
    add constraint payments_user_fk
        foreign key (user_id) references users (id)
        on delete restrict on update restrict,
    add constraint payments_ticket_fk
        foreign key (ticket_id) references tickets (id)
        on delete restrict on update restrict,
    add constraint payments_amount_non_negative
        check (amount >= 0),
    add constraint payments_currency_iso_shape
        check (currency ~ '^[A-Z]{3}$'),
    add constraint payments_status_known
        check (status in ('Pending', 'Captured', 'Failed', 'Refunded')),
    add constraint payments_reference_canonical
        check (external_payment_reference is null
                or (external_payment_reference <> ''
                    and external_payment_reference = btrim(external_payment_reference))),
    add constraint payments_captured_has_reference
        check (status <> 'Captured' or external_payment_reference is not null);

-- Partial unique index: the rule is "one captured payment per gateway
-- reference", not "a reference may never appear twice". Other statuses may
-- legitimately carry the same reference (e.g. the failed or refunded leg of the
-- same gateway transaction), so only 'Captured' rows compete.
create unique index payments_captured_reference_unique
    on payments (external_payment_reference)
    where status = 'Captured';

-- ---------------------------------------------------------------------------
-- validations (INV-12, INV-13, INV-14)
-- ---------------------------------------------------------------------------
-- validations.ticket_code duplicates tickets.ticket_code (it is functionally
-- determined by ticket_id). Two ways to stop that copy from lying:
--   (a) drop the column and join through ticket_id;
--   (b) keep it and make the database prove the pair is real.
-- This migration takes (b): a composite foreign key on (ticket_id, ticket_code)
-- means a validation can never pair one ticket's id with another ticket's
-- code, and ON UPDATE RESTRICT means a validated ticket's code can no longer be
-- edited, which would silently change what the historical scan meant.
-- The trade-off is redundant storage; see the issue register.
alter table validations
    alter column ticket_id set not null,
    alter column ticket_code set not null,
    alter column result set not null,
    alter column validated_utc set not null,
    add constraint validations_ticket_fk
        foreign key (ticket_id, ticket_code) references tickets (id, ticket_code)
        on delete restrict on update restrict,
    add constraint validations_stop_fk
        foreign key (stop_id) references stops (id)
        on delete restrict on update restrict,
    add constraint validations_result_known
        check (result in ('Accepted', 'Rejected'));

commit;
