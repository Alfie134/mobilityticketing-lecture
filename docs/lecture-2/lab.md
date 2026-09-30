# Lecture 2: Make invalid states difficult to store

Task: strengthen the ticketing schema (trips, products, users, tickets,
payments, validations) so that the **database** refuses states that conflict
with the case, regardless of which application, script or future service does
the write.

Deliverables in this repository:

| What                                                  | Where                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| Migration                                             | `database/postgres/migrations/011_ticketing_integrity.sql` |
| Negative (and positive) tests                         | `database/postgres/tests/constraints_test.sql`             |
| Integrity map, issue register, state-transition trace | [`integrity-map.md`](integrity-map.md)                     |
| Invariants, decisions, evidence (this file)           | `docs/lecture-2/lab.md`                                    |

## How to run

```bash
docker compose down -v && docker compose up -d          # init/ scripts: weak starter schema
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 \
    < database/postgres/migrations/011_ticketing_integrity.sql
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 \
    < database/postgres/tests/constraints_test.sql       # exit status 0 = all pass
```

The migration is a one-shot: applying it twice fails because the constraints
already exist. To replay, recreate the database (`down -v`).

## 1. Result

- The migration applies in a single transaction (all rules or none).
- Against the **weak starter schema, before the migration**, all 35 rejection
  tests failed (the invalid write was accepted). That is the check that the
  tests can fail at all.
- After the migration: **47 of 47 pass** (35 writes rejected, 12 writes
  accepted). Every rejection is asserted on both the SQLSTATE **and the exact
  constraint name**, so a write rejected by the wrong rule is a failure.
- The 10 statements in the instructor's `experiments/constraints_should_fail.sql`
  are each rejected by a named constraint.
- The suite rolls every statement back; the seed data is identical before and
  after, and the suite can be re-run.

## 2. Invariant catalogue and classification

Classes: **A** column/table constraint (`NOT NULL`, `CHECK`, foreign key) ·
**B** unique or exclusion rule · **C** depends on more than one row or an
external system · **D** currently ambiguous, needs a domain decision.

| ID     | Invariant                                                                                                                      | Class               | Status                                 |
| ------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------- | -------------------------------------- |
| INV-01 | A trip's capacity is present and never negative                                                                                | A                   | Enforced                               |
| INV-02 | `reserved_seats` is present and between 0 and `capacity` (same row)                                                            | A                   | Enforced (row only, see INV-18)        |
| INV-03 | Trip status is one of Scheduled, Cancelled, Completed                                                                          | A                   | Enforced                               |
| INV-04 | Product price, ticket price and payment amount are present and never negative                                                  | A                   | Enforced                               |
| INV-05 | Currency is present and written as three uppercase letters                                                                     | A                   | Enforced (shape only, see INV-27)      |
| INV-06 | Ticket status, payment status and validation result come from known sets                                                       | A                   | Enforced                               |
| INV-07 | A ticket's validity end is not earlier than its start                                                                          | A                   | Enforced                               |
| INV-08 | A ticket code is non-empty and has no leading/trailing whitespace                                                              | A                   | Enforced                               |
| INV-09 | A captured payment carries a gateway reference                                                                                 | A                   | Enforced                               |
| INV-10 | A ticket refers to an existing user, trip and product                                                                          | A (FK)              | Enforced                               |
| INV-11 | A payment refers to an existing ticket and user                                                                                | A (FK)              | Enforced                               |
| INV-12 | A validation refers to an existing ticket, and its ticket id and code belong to the _same_ ticket                              | A (composite FK)    | Enforced                               |
| INV-13 | A validation's stop, when given, exists                                                                                        | A (FK)              | Enforced                               |
| INV-14 | Tickets, payments and validations cannot be orphaned or re-keyed by changes to their parents                                   | A (FK `RESTRICT`)   | Enforced                               |
| INV-15 | A ticket code identifies at most one ticket                                                                                    | B                   | Enforced                               |
| INV-16 | A user email is present and unique, ignoring case                                                                              | B                   | Enforced                               |
| INV-17 | One gateway reference is recorded as captured at most once                                                                     | B (partial unique)  | Enforced                               |
| INV-18 | Seats sold never exceed capacity under concurrent purchases; `reserved_seats` agrees with the tickets that exist               | C                   | **Deferred** (transactions)            |
| INV-19 | A ticket is `Active` only if a captured payment for it exists; gateway capture and the database write succeed or fail together | C (external system) | **Deferred** (transactions / workflow) |
| INV-20 | A ticket is only sold for a `Scheduled` trip                                                                                   | C                   | Deferred                               |
| INV-21 | A disabled user cannot buy a ticket                                                                                            | C / D (policy)      | Deferred                               |
| INV-22 | An accepted validation falls inside the validity window of an `Active` ticket, and a ticket is accepted at most once           | C                   | **Deferred** (transactions)            |
| INV-23 | A ticket's price equals the product's price at purchase time                                                                   | C                   | Deferred (needs price history)         |
| INV-24 | A payment's amount and currency match its ticket; a payment's user owns the ticket                                             | C / D               | Deferred                               |
| INV-25 | May someone pay for a ticket they do not own?                                                                                  | D                   | Open decision                          |
| INV-26 | Are refunds separate negative rows, or status changes? Can a payment be exactly 0?                                             | D                   | Open (0 allowed today)                 |
| INV-27 | Currency must be a real ISO 4217 code; monetary precision per currency                                                         | D                   | Open (shape only today)                |
| INV-28 | Does `service_date` agree with the departure timestamp, and in which time zone?                                                | D                   | Open                                   |
| INV-29 | Where are rejected scans of unknown codes recorded; are stop, vehicle and device mandatory on a validation?                    | D                   | Open                                   |

## 3. Decisions I had to make

The brief leaves these to the student. Each is a defensible choice, not the only
one.

1. **Status vocabularies.** Trips: `Scheduled`, `Cancelled`, `Completed`.
   Tickets: `Pending`, `Active`, `Validated`, `Cancelled`, `Expired`. Payments:
   `Pending`, `Captured`, `Failed`, `Refunded`. Validations: `Accepted`,
   `Rejected`. The payment and validation sets are my own choice, because the
   scenario does not list them. Delays are deliberately not a trip status; they
   belong to the real-time workload.
2. **`validations.ticket_code` is kept and protected with a composite foreign
   key** `(ticket_id, ticket_code) -> tickets (id, ticket_code)`. The alternative
   is to drop the column and join through `ticket_id`, which removes the
   redundancy (and the invariant) altogether. I kept it because the instructor's
   experiment #10 presupposes it, and because it records exactly what the scanner
   read. The cost is a duplicated value plus an extra unique constraint
   (`tickets_id_code_unique`) that exists only to be a foreign-key target.
3. **`external_payment_reference` is nullable, but required once `Captured`.** A
   `Pending` payment may be created before the gateway has answered, so a blanket
   `NOT NULL` would forbid that step.
4. **"Not recorded twice" is a partial unique index** on rows where
   `status = 'Captured'`. The brief says "if it represents one captured payment",
   so a failed or refunded leg of the same gateway transaction may share a
   reference. A plain `UNIQUE` would be stricter but would reject that.
5. **Ticket price is a snapshot,** not a reference to the product price, so
   raising a price later does not rewrite issued tickets. The price of that
   choice is INV-23.
6. **Deletion is restricted; things are retired by state.** See section 5.
7. **Email uniqueness ignores case** (`unique index on lower(email)`).
8. **Currency is checked for shape** (`^[A-Z]{3}$`), not membership.

## 4. Evidence per implemented invariant

Test id's are in `constraints_test.sql`. "F" tests must be rejected, "S" tests
must be accepted. The error column is SQLSTATE plus constraint (or column for
`NOT NULL`).

| Rule                                       | DDL                                                                                         | Accepted write                         | Rejected write                                           | Error                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------- | -------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------- |
| INV-01 capacity present, >= 0              | `trips.capacity NOT NULL`, `trips_capacity_non_negative`                                    | S10 (capacity 0)                       | F01 (-1), F02 (null)                                     | `23514` `trips_capacity_non_negative`, `23502` `capacity` |
| INV-02 0 <= reserved <= capacity           | `trips_reserved_seats_valid`                                                                | S01 (reserved = capacity)              | F03 (capacity + 1), F04 (-1)                             | `23514` `trips_reserved_seats_valid`                      |
| INV-03 trip status known                   | `trips_status_known`                                                                        | S11 (set `Cancelled`)                  | F05 (`Delayed`)                                          | `23514` `trips_status_known`                              |
| INV-04 money not negative                  | `products_price_non_negative`, `tickets_price_non_negative`, `payments_amount_non_negative` | S02 (price 0), S04, S07                | F06, F07, F08                                            | `23514` on each named constraint                          |
| INV-05 currency present and shaped         | `*_currency_iso_shape`, `currency NOT NULL`                                                 | S04, S07 (`DKK`)                       | F09 (`dkk`), F10 (null), F11 (`DK`)                      | `23514` `*_currency_iso_shape`, `23502` `currency`        |
| INV-06 known status sets                   | `tickets_status_known`, `payments_status_known`, `validations_result_known`                 | S04, S05, S07, S08                     | F12, F13, F14                                            | `23514` on each named constraint                          |
| INV-07 validity end >= start               | `tickets_validity_window_valid`                                                             | S03 (equal), S04                       | F15 (reversed)                                           | `23514` `tickets_validity_window_valid`                   |
| INV-08 canonical ticket code               | `tickets_ticket_code_canonical`                                                             | S04                                    | F16 (trailing space), F17 (empty)                        | `23514` `tickets_ticket_code_canonical`                   |
| INV-09 captured has reference              | `payments_captured_has_reference`, `payments_reference_canonical`                           | S05 (Pending, no reference), S07       | F18                                                      | `23514` `payments_captured_has_reference`                 |
| INV-10 ticket refs                         | `tickets_user_fk`, `tickets_trip_fk`, `tickets_product_fk`                                  | S04                                    | F19, F20, F21                                            | `23503` on each named FK                                  |
| INV-11 payment refs                        | `payments_ticket_fk`, `payments_user_fk`                                                    | S07                                    | F22, F23                                                 | `23503` on each named FK                                  |
| INV-12 validation refs, id/code pair       | `validations_ticket_fk` (composite)                                                         | S08                                    | F24 (unknown ticket), F25 (id of one, code of another)   | `23503` `validations_ticket_fk`                           |
| INV-13 stop exists                         | `validations_stop_fk`                                                                       | S08                                    | F26                                                      | `23503` `validations_stop_fk`                             |
| INV-14 history not orphaned                | all FKs `ON DELETE/UPDATE RESTRICT`                                                         | S12 (trip with no tickets deletes)     | F27-F30 (deletes), F31 (edit code of a validated ticket) | `23503` on the referencing FK                             |
| INV-15 unique ticket code                  | `tickets_ticket_code_unique`                                                                | S04                                    | F32                                                      | `23505` `tickets_ticket_code_unique`                      |
| INV-16 email present, unique ignoring case | `email NOT NULL`, `users_email_lower_unique`                                                | S09                                    | F33 (`ANNA@...`), F34 (null)                             | `23505` `users_email_lower_unique`, `23502` `email`       |
| INV-17 one captured payment per reference  | `payments_captured_reference_unique` (partial)                                              | S06 (a `Failed` row may reuse it), S07 | F35                                                      | `23505` `payments_captured_reference_unique`              |

Assertions use SQLSTATE and constraint name, never message text, because
messages depend on server language and version.

## 5. Delete and update behaviour

Tickets, payments and validations are compliance history (the brief requires
long-term storage for reporting and compliance), so the default is: **the
parent cannot be deleted or re-keyed while history points at it.** Retirement is
expressed as state, not deletion.

| Relationship                     | Delete parent  | Update parent key                                             | How something is retired instead                     |
| -------------------------------- | -------------- | ------------------------------------------------------------- | ---------------------------------------------------- |
| ticket -> user                   | Restrict (F28) | Restrict                                                      | `users.is_disabled`                                  |
| ticket -> trip                   | Restrict (F29) | Restrict                                                      | `trips.status = 'Cancelled'`                         |
| ticket -> product                | Restrict (F30) | Restrict                                                      | No `active` flag exists yet (gap, see integrity map) |
| payment -> ticket                | Restrict (F27) | Restrict                                                      | Payments are financial records: never deleted        |
| payment -> user                  | Restrict       | Restrict                                                      | as above                                             |
| validation -> ticket (id + code) | Restrict       | Restrict, so a validated ticket's code cannot be edited (F31) | Ticket `status`                                      |
| validation -> stop               | Restrict       | Restrict                                                      | n/a                                                  |

Cascade is not used anywhere: a cascading delete of a user or ticket would
silently erase payments and validations, which is exactly what compliance
retention forbids. Soft deletion is used where the schema already has the
column (`is_disabled`, trip and ticket `status`); a retention policy for
eventual archiving is not designed yet.

**What is not protected:** the rules above stop _deleting and re-keying_, but
not _editing the value that carries meaning_. A captured payment's `amount` and a
ticket's `price` can still be changed after the fact (evidence L1 in the integrity
map). Closing that needs append-only design, column privileges or triggers, and is
out of scope for constraints.

## 6. Invariants that a simple constraint cannot solve

Kept for the transactions lecture (full evidence in the issue register):

1. **Seat capacity under concurrent purchase (INV-18).** `reserved_seats <=
capacity` is a check on one row. Two purchases that both read the same
   remaining capacity can each pass it and together oversell. The seed already
   shows the counter is a separate fact from the tickets: `TRIP-M2-20260429-0800`
   has `reserved_seats = 2` but one live ticket, and nothing can say which is
   right.
2. **Payment capture across the gateway and PostgreSQL (INV-19).** The database
   cannot know whether the gateway captured money. A crash between "captured" and
   "row written" leaves a customer charged with no ticket. The partial unique
   index on captured references only stops recording the same capture twice; it
   is not a workflow.
3. **Validation rules that read other rows (INV-22).** Accepting a scan requires
   an `Active` ticket inside its window and no earlier accepted scan; the ticket
   must then move to `Validated`. Today two accepted validations for the same
   ticket are stored while the ticket stays `Active` (L5).

## 7. Assumption from lecture 1, revisited

Lecture 1 stored trip `status` as unconstrained text and flagged it as an
assumption that would change. It has: `trips_status_known` now constrains it. The
lecture 1 seed used lowercase `'scheduled'`; the lecture 2 starter uses
`'Scheduled'`, and the constraint follows the latter.

## 8. Scope notes

- Tests are SQL run inside PostgreSQL, so they need only `psql`. They assert the
  same things a .NET integration test would (`PostgresException.SqlState` plus
  `ConstraintName`) and can be ported to xUnit/Npgsql if the course requires.
- No indexes were added on foreign-key columns (for example
  `payments.ticket_id`). Indexing is a workload question for a later lecture.
- I verified everything on PostgreSQL 16; the course image is
  `postgres:17-alpine`. Nothing used is version-specific, but run the three
  commands under "How to run" once against the Docker image before submitting.
