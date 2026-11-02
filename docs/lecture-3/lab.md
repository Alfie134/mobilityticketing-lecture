# Lecture 3: Where should reporting logic execute?

Task: implement and compare four ways of answering "daily captured revenue
by operator" (a direct query, a function, a materialized view, and a
trigger-maintained summary table), then decide, with evidence, where the
responsibility for that number belongs.

All numbers below come from commands run against a live PostgreSQL 17
container. Payment IDs (`PAYMENT-1`, `PAYMENT-2`, `PAY-NEW-1`, `PAY-CASE1`,
`PAY-CASE2`, `PAY-CASE1-DUP`) match the seed and test data actually used.

## 0. Environment notes (read before running anything)

Two problems in the repository were found and fixed before any of the four
approaches could be tested. Both must be committed, not just fixed in the
running container:

1. **`init/` seed files had corrupted lines left over from lecture 2.** A
   stray `.` after a column definition in `001_relational_baseline.sql`; a
   misspelled `route_stops` column list in `002_seed.sql` (`route id` and
   `sequence_id` instead of `route_id` and `stop_sequence`); a trailing comma
   before an `on conflict` clause; a second `route_stops` insert with no value
   rows; and a misspelled `scheduled_depature_utc` column in the trips insert.
   On a fresh `docker compose down -v && up -d` these stop the `init/` scripts.
2. **`011_ticketing_integrity.sql` assumes every `trips` row has a non-null
   `capacity`.** The five oldest seed trips were inserted before `capacity`
   existed as a column, so `alter column capacity set not null` fails on a
   fresh database. Add this line right after the opening `begin;` and before
   the first `alter table trips`:

   ```sql
   update trips set capacity = 40, reserved_seats = 0 where capacity is null;
   ```

   This makes the migration work on every reset instead of only working
   because the live container was patched by hand.

## 1. Task 1: reference query, verified against base tables

`database/postgres/queries/base_revenue.sql`:

```sql
select
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
```

Initial result, before any test data was added:

```
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-BUS      | 2026-04-29   |           36.00 |                 1
 OP-METRO    | 2026-04-29   |           36.00 |                 1
```

Manual verification of the `OP-BUS` row, re-derived from the raw `payments`
rows instead of trusting the aggregate:

```sql
select p.id, p.amount, p.status, p.created_utc, r.operator_id
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where r.operator_id = 'OP-BUS' and p.created_utc::date = '2026-04-29';
```

```
    id     | amount |  status  |      created_utc       | operator_id
-----------+--------+----------+------------------------+-------------
 PAYMENT-2 |  36.00 | Captured | 2026-04-29 08:40:00+00 | OP-BUS
```

One row, `Captured`, `36.00`, dated `2026-04-29`: it matches the aggregate.

## 2. Task 2: SQL function

`database/postgres/migrations/020_reporting_function.sql` (applied as supplied):

```sql
create or replace function captured_revenue_for_day(
    requested_operator_id text,
    requested_date date
)
returns table (
    captured_amount numeric,
    captured_payments bigint
)
language sql
stable
as $$
    select
        coalesce(sum(p.amount), 0),
        count(*)
    from payments p
    join tickets t on t.id = p.ticket_id
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where r.operator_id = requested_operator_id
      and p.created_utc::date = requested_date
      and p.status = 'Captured';
$$;
```

`stable` promises that within one query, calling the function twice with the
same arguments returns the same answer, so the planner may reuse the result.
The function still reads tables, but it must not write.

Verified against the same row as task 1:

```sql
select * from captured_revenue_for_day('OP-BUS', '2026-04-29');
```

```
 captured_amount | captured_payments
-----------------+-------------------
           36.00 |                 1
```

Called with a date that has no data, to check the `coalesce`:

```sql
select * from captured_revenue_for_day('OP-BUS', '2099-01-01');
```

```
 captured_amount | captured_payments
-----------------+-------------------
               0 |                 0
```

`count(*)` over zero rows is `0`; `sum()` over zero rows is `NULL`, which is
why only the `sum` is wrapped in `coalesce(..., 0)`.

**A first, structural difference between two approaches:** for an operator and
date with zero captured payments, `base_revenue.sql` returns no row at all (there
is nothing to `group by`), while the function returns one row of zeroes. Same
truth ("no captured revenue that day"), two representations.

## 3. Task 3: materialized view, and observing staleness

```sql
create materialized view daily_captured_revenue as
    select
        r.operator_id,
        p.created_utc::date as revenue_date,
        sum(p.amount) as captured_amount,
        count(*) as captured_payments
    from payments p
    join tickets t on t.id = p.ticket_id
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where p.status = 'Captured'
    group by r.operator_id, p.created_utc::date;
```

This is the `base_revenue.sql` query with `create materialized view ... as` in
front of it. A materialized view is not a different kind of query; it is an
instruction to run a trusted query once and physically store the result.

**Before** (right after creation, matching task 1 because the defining query ran
against everything that already existed):

```
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-BUS      | 2026-04-29   |           36.00 |                 1
 OP-METRO    | 2026-04-29   |           36.00 |                 1
```

**Event:** inserted a new captured payment for `OP-METRO` (`PAY-NEW-1`, ticket
`TICKET-1`, which belongs to `LINE-M2` and so to `OP-METRO`; amount 50).

**After the insert, view not refreshed** (stale):

```
select * from daily_captured_revenue where operator_id = 'OP-METRO';
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-METRO    | 2026-04-29   |           36.00 |                 1
```

**Same moment, function** (computed fresh):

```
select * from captured_revenue_for_day('OP-METRO', '2026-04-29');
 captured_amount | captured_payments
-----------------+-------------------
           86.00 |                 2
```

**Captured example where two approaches disagree:** same table, same instant,
`OP-METRO` on `2026-04-29`. The materialized view says `36.00 / 1`; the function
and `base_revenue.sql` say `86.00 / 2`. This is what "materialized" means: the
view keeps saying the old number until something tells it to recompute.

**After `refresh materialized view daily_captured_revenue;`** the defining query
reruns against the current table, so the view catches up to `86.00 / 2`.
Re-run the `select` above once more before submitting and paste the literal
output here; the refreshed row was reasoned through live but not copied into
the notes.

**Stale is not wrong.** The view never runs a wrong query. It is stale for a
bounded window that one command (`refresh`) always closes completely.

## 4. Task 4: trigger-maintained summary table

`database/postgres/migrations/021_daily_revenue_trigger.sql`, applied as
supplied and deliberately incomplete:

```sql
create table daily_revenue_by_operator (
    operator_id text not null references operators(id),
    revenue_date date not null,
    captured_amount numeric not null default 0,
    captured_payments bigint not null default 0,
    primary key (operator_id, revenue_date)
);

create or replace function add_inserted_payment_to_daily_revenue()
returns trigger
language plpgsql
as $$
declare
    payment_operator_id text;
begin
    if new.status is distinct from 'Captured' then
        return new;
    end if;

    select r.operator_id
    into payment_operator_id
    from tickets t
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where t.id = new.ticket_id;

    insert into daily_revenue_by_operator (
        operator_id, revenue_date, captured_amount, captured_payments
    ) values (
        payment_operator_id, new.created_utc::date, new.amount, 1
    )
    on conflict (operator_id, revenue_date)
    do update set
        captured_amount = daily_revenue_by_operator.captured_amount + excluded.captured_amount,
        captured_payments = daily_revenue_by_operator.captured_payments + 1;

    return new;
end;
$$;

create trigger payments_daily_revenue_after_insert
after insert on payments
for each row
execute function add_inserted_payment_to_daily_revenue();
```

(Check this block against your own `021` file and paste your actual file if
they differ.)

**Immediately after creation, before any new insert:**

```sql
select * from daily_revenue_by_operator;
```

```
(0 rows)
```

**Why empty, not stale:** a trigger only reacts to events after it exists.
`PAYMENT-1` and `PAYMENT-2` were inserted before the trigger, so it never saw
them. This is a different failure from the view's staleness. The view had the
full history from creation and drifts forward; the trigger table never had any
history. There is no equivalent of `refresh`; the only fix is a manual backfill
query.

**Consequence for every later scenario:** from its first insert onward, this
table is short by `PAYMENT-2`'s `36.00` for `OP-BUS` (and `PAYMENT-1`'s for
`OP-METRO`). Its running total was never right, even when its increment logic
was.

## 5. Task 5: the six test scenarios

All run in this order against `OP-BUS`. `base_revenue.sql` is ground truth.

| #   | Scenario                                 | Statement                                                                                                              | `base_revenue.sql`                                                                                                 | `daily_revenue_by_operator`                                                                                                                            |
| --- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0   | Starting point                           | none                                                                                                                   | 36.00 / 1                                                                                                          | table empty (no backfill)                                                                                                                              |
| 1   | Captured insert                          | `insert ... ('PAY-CASE1', 'USER-2', 'TICKET-2', 'gateway-case1', 40, 'DKK', 'Captured', '2026-04-29 10:00:00+00')`     | **76.00 / 2**                                                                                                      | **40.00 / 1**: the +40 increment is right, the total is short by the 36.00 that predates the trigger                                                   |
| 2   | Failed insert                            | `insert ... ('PAY-CASE2', 'USER-2', 'TICKET-2', 25, 'DKK', 'Failed', '2026-04-29 11:00:00+00')`                        | 76.00 / 2 (unchanged)                                                                                              | 40.00 / 1 (unchanged; correctly ignored by `if new.status is distinct from 'Captured'`)                                                                |
| 3   | Failed to Captured                       | `update payments set status = 'Captured', external_payment_reference = 'gateway-case2-retry' where id = 'PAY-CASE2'`   | **101.00 / 3**                                                                                                     | **40.00 / 1, silently wrong.** No `after update` trigger exists, so the real 25.00 never reaches the table                                             |
| 4   | Captured to Refunded                     | `update payments set status = 'Refunded' where id = 'PAY-CASE2'`                                                       | 76.00 / 2 (drops back correctly)                                                                                   | **40.00 / 1, still silently wrong.** Even with an `after update` trigger, this function has no branch that subtracts a refunded amount                 |
| 5   | Delete the refunded row                  | `delete from payments where id = 'PAY-CASE2'`                                                                          | 76.00 / 2 (unchanged; the row was `Refunded`, so it was never counted)                                             | 40.00 / 1 (unchanged by the delete, which is the right delta here since the row was never counted; the table is still short by the 36.00 backfill gap) |
| 6   | Duplicate delivery of the same reference | `insert ... ('PAY-CASE1-DUP', 'USER-2', 'TICKET-2', 'gateway-case1', 40, 'DKK', 'Captured', '2026-04-29 10:05:00+00')` | **`ERROR: duplicate key value violates unique constraint "payments_captured_reference_unique"`**, nothing recorded | 40.00 / 1 (unchanged: the insert never completed, so the trigger never fired)                                                                          |

**Scenario 6 is not evidence the trigger handles duplicates.** A different
mechanism, last week's partial unique index `payments_captured_reference_unique`
on `external_payment_reference where status = 'Captured'`, stops the bad row from
being written, so the trigger never gets the chance to double-count. Without that
constraint this trigger would add the duplicate, because nothing in its code
checks whether a reference was seen before. `external_payment_reference` is the
gateway's own transaction identifier; `id` is this database's key. Two different
`id`s can carry the same gateway reference, which is exactly what a redelivered
notification looks like.

**Scenarios 3 and 4 look consistent only at the edges.** After scenario 4, both
`base_revenue.sql` (76.00 / 2) and the trigger table (40.00 / 1) show the same
numbers they showed after scenario 1. They got there differently: the trigger
table never moved across scenarios 2 to 5, while `base_revenue.sql` recomputed
twice (add 25, subtract it again). Anyone reading the trigger table between
scenarios 3 and 4 got a number that was wrong, with no error and no warning.

## 6. Task 6: responsibility matrix

| Dimension                  | `base_revenue.sql`                                        | Function                                                       | Materialized view                                                                                                             | Trigger table                                                                                                                                                                                                                                                |
| -------------------------- | --------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Correctness**            | Always correct: recomputes from base tables on every call | Always correct, same reason, narrowed to one operator and date | Correct right after creation or a `refresh`; wrong (stale) whenever `payments` has changed since                              | Never correct as a total in this lab: it started empty, so it was below the truth from its first insert. Its increment logic is right only for a brand-new `Captured` insert; scenarios 3 and 4 proved it silently wrong with no way to detect or correct it |
| **Freshness**              | Always current                                            | Always current                                                 | Stale between refreshes, but the window is a controllable choice: refresh when current data is needed                         | Not controllable. No operation catches it up. Current only for one event type (insert) and one status (`Captured`)                                                                                                                                           |
| **Write cost**             | None, read-only                                           | None, read-only                                                | None until `refresh`, which then recomputes the whole view                                                                    | Every payment insert now also does a three-table lookup and an upsert, forever                                                                                                                                                                               |
| **Read cost**              | Full join and aggregate on every call                     | Full join and aggregate on every call, narrowed to one row     | Cheap: reads stored rows, no joins at read time                                                                               | Cheap: same as the view                                                                                                                                                                                                                                      |
| **Hidden side effects**    | None: a pure read writes nothing                          | None                                                           | None from reading it; `refresh` rebuilds the stored result (a real operational cost at scale, not observed as a problem here) | The only approach with a hidden side effect: an `insert into payments` silently writes to a second table the caller may not know exists                                                                                                                      |
| **Rebuildability**         | Nothing stored, nothing to rebuild                        | Nothing stored, nothing to rebuild                             | Trivial and complete: `refresh materialized view daily_captured_revenue;` recomputes the truth from `payments`                | No rebuild command exists. A rebuild means a hand-written backfill, and nothing records what was already counted, so a double-backfill is easy to do by mistake                                                                                              |
| **Operational complexity** | Lowest: one query                                         | Low: one function, one trusted definition                      | Medium: something must call `refresh` on a schedule someone has chosen                                                        | Highest: correctness depends on everyone who ever changes `payments` also extending the trigger for every new kind of change, and it gives no warning when they forget                                                                                       |

**Authority and rebuild path for each stored copy:** the authority for every
number here is `payments` joined to `tickets`, `trips` and `routes`. The view is
rebuilt by `refresh`. The trigger table has no rebuild path beyond a manual
truncate-and-reload from the same query.

## 7. Side-effect trace for one payment write

Scenario 1: `insert into payments (id, user_id, ticket_id,
external_payment_reference, amount, currency, status, created_utc) values
('PAY-CASE1', 'USER-2', 'TICKET-2', 'gateway-case1', 40, 'DKK', 'Captured',
'2026-04-29 10:00:00+00')`.

1. `NOT NULL` on `user_id`, `ticket_id`, `amount`, `currency`, `status`,
   `created_utc`: satisfied.
2. `payments_amount_non_negative`: `40 >= 0`, passes.
3. `payments_currency_iso_shape`: `'DKK'` matches `^[A-Z]{3}$`, passes.
4. `payments_status_known`: `'Captured'` is in the set, passes.
5. `payments_reference_canonical`: non-empty, no surrounding whitespace, passes.
6. `payments_captured_has_reference`: status is `Captured` and a reference is
   present, passes.
7. `payments_captured_reference_unique` (partial unique index): no other
   `Captured` row has `gateway-case1`, passes. This is the check that rejects
   the duplicate in scenario 6.
8. `payments_ticket_fk`: `TICKET-2` exists, passes.
9. `payments_user_fk`: `USER-2` exists, passes.
10. The row is written to `payments`.
11. `payments_daily_revenue_after_insert` fires (after insert, once per row):
    a. `new.status` is `Captured`, so the function does not exit early.
    b. A lookup joins `tickets`, `trips` and `routes` for `TICKET-2` and
    resolves the operator (`OP-BUS`).
    c. An upsert on `daily_revenue_by_operator` for `('OP-BUS', '2026-04-29')`:
    inserts a new row if none exists, otherwise adds 40 to the amount and 1
    to the count.
12. Net effect of one statement: one row in `payments`, nine constraint checks,
    three tables read inside the trigger, and one row inserted or updated in
    `daily_revenue_by_operator`. `base_revenue.sql` and the function are
    untouched, since they only ever read.

To capture this as measured evidence instead of a walkthrough, run
`explain (analyze, costs off)` on an insert inside `begin; ... rollback;`: it
lists the foreign-key triggers and the summary trigger with their call counts
and times.

## 8. Recommendation

**Serve this report with the function. Add the materialized view only if
measured read volume on the live join becomes a problem. Do not use the
trigger table as designed.**

This follows from the reporting workload in the brief: reporting "can tolerate
more latency than purchase and validation" and "does not need to reflect every
operational write immediately".

- The **function** is always correct, costs nothing on writes, has no hidden side
  effects and needs no upkeep. Its one cost (recomputing the join each call) is
  exactly the latency the brief says reporting may spend. For an operator
  dashboard read occasionally, that cost is not a problem.
- If read volume outgrows the live join, add the **materialized view**,
  refreshed on a schedule. Its staleness is bounded, visible and fixed
  completely by one command, which fits the brief's tolerance.
- The **trigger table** should not be used. It adds write cost to the
  correctness-critical purchase path in order to buy instant freshness that this
  workload does not need and that this implementation does not deliver: it was
  short from its first insert (no backfill) and silently wrong for a late capture
  and a refund. Making it correct means adding update and delete handling,
  refund reversal and a backfill procedure, which makes it the most complex
  option for the workload that needs it least.

No hybrid is recommended: the function alone meets the workload, so a second
stored copy would only add complexity for freshness nobody asked for. If one is
added later, `payments` stays the authority, and the view's rebuild path
(`refresh`) is trivial.

## Submission checklist

- [x] Reference query run, one row verified against raw `payments` data
- [x] SQL function created and verified, `coalesce` checked on a zero-row case
- [x] Materialized view created, staleness observed and captured
- [x] Supplied trigger table created, no-backfill gap observed
- [x] All six scenarios run, before and after captured
- [x] One captured disagreement (section 3, `OP-METRO`, view vs function)
- [x] Recommendation drafted (section 8)
- [ ] Side-effect trace items 4 to 7: rows and locks touched, commit or rollback behaviour, when each report becomes current, what the application can observe (section 7 covers items 1 to 3 only)
- [ ] Responsibility matrix: add explicit rows for named authority, freshness rule and rebuild path (section 6 has the seven dimensions, but these three are only in prose)
- [ ] One issue in the issue register
- [ ] One defended decision record
- [ ] Recommendation: say explicitly how it handles coupling, correction behaviour, duplicate delivery, observability and recovery
- [ ] Add the `capacity` backfill line to `011_ticketing_integrity.sql` (section 0)
- [ ] Re-run the post-refresh `select` from section 3 and paste the output
- [ ] Check the trigger block in section 4 against your own `021` file
