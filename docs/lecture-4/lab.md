# Lecture 4: Changing a populated database safely (product_code to product_id)

Goal: change `tickets` so it refers to a product by `product_id` (uuid) instead
of `product_code`, without breaking existing data or old code half way through.
The method is expand, backfill, verify, contract: add the new thing next to the
old one, copy the data across, check it, make the new thing required, and only
then remove the old thing.

All outputs below were produced against PostgreSQL 17 in the course container.
Files live in `database/postgres/migrations/` (030 to 034) and
`database/postgres/experiments/lecture04/`.

## Step 1: starting data

Added `TICKET-3` on the `DAY` product so the data has three tickets across two
products.

```
select code, name, price, currency from products:
  DAY    | Day pass    | 80.00 | DKK
  SINGLE | Single trip | 36.00 | DKK
```

`baseline.sql` saved to `experiments/lecture04/`, output kept in
`baseline_before.txt`. The check for tickets pointing at a missing product
returned zero rows. The fingerprint of the original tickets:

```
 TICKET-1 | SINGLE | 36.00 | DKK
 TICKET-2 | SINGLE | 36.00 | DKK
 TICKET-3 | DAY    | 80.00 | DKK
```

## Step 2: the bad version, tried first

`bad_migration.sql` ran inside a transaction that ends in `rollback`, so nothing
was kept (`baseline.sql` run afterwards still showed the three tickets with
their `product_code`).

```sql
begin;
alter table tickets drop column product_code;
savepoint after_drop;
alter table tickets add column product_id uuid not null;   -- fails
rollback to savepoint after_drop;                          -- go back to just after the drop
select id, product_code, price, currency from tickets order by id;   -- fails
rollback;                                                  -- undo everything
```

The savepoint lets the script keep going after the first error, so both failures
show up in one run.

Errors received:

```
ERROR:  column "product_id" of relation "tickets" contains null values
ERROR:  column "product_code" does not exist
```

**Why it is unsafe.** Existing tickets have no way to get a `product_id`:
dropping `product_code` first destroys the only link between a ticket and its
product before anything has been copied, and a new required column cannot be
added while existing rows have no value for it. Code that still reads
`product_code`, including the baseline query, breaks the moment the column is
gone. A populated database has to change in steps where old and new code keep
working, because unlike a new database it has existing rows that must stay valid
at every step.

## Step 3: expand (`030_expand_product_identity.sql`)

Applied as supplied. Products got a uuid `id` (default `gen_random_uuid()`,
`not null`, unique). `tickets.product_id` was added as nullable, with a foreign
key created `not valid`, which checks new rows but skips existing ones until
Step 6. `set local lock_timeout = '3s'` makes the migration give up after three
seconds instead of queueing behind another session's lock.

After running: both products have a uuid, all three tickets keep their
`product_code`, `product_id` is empty, and the baseline queries still work.

Note: a first run failed with `column "product_id" of relation "tickets" already
exists` because the file contained a duplicated `add column` line. The migration
is one transaction, so the failed run changed nothing. After removing the
duplicate line it applied cleanly.

## Step 4: old and new code side by side

Scripts: `old_writer.sql` (only `product_code`), `new_writer.sql` (takes a
`product_id` and derives the code, price and currency from the product row),
`old_reader.sql`, `new_reader.sql` (the brief's query), `mismatch.sql`.

Results: both writers insert, the old reader lists tickets by `product_code`, and
the new reader (the brief's `coalesce` query) resolves every ticket to a product
id. At this point `TICKET-1` to `TICKET-3` still have no `product_id`, so they
resolve through the `product_code` fallback, while the new ticket resolves through
its `product_id`. All four rows resolved correctly:

```
 TICKET-1            | c4f84945-...  (SINGLE)
 TICKET-2            | c4f84945-...  (SINGLE)
 TICKET-3            | 5f87ed28-...  (DAY)
 TICKET-NEW-5b3070df | 5f87ed28-...  (DAY)
```

**Mismatch test** (`product_code = 'SINGLE'` with the `DAY` product's id, inside
a rolled-back transaction):

```
       id        | product_code |              product_id              | code_of_that_id
 TICKET-MISMATCH | SINGLE       | 5f87ed28-2039-4f6c-b26f-0759ca760c06 | DAY
```

- **Does the new writer prevent it? Yes.** It derives the code from the product
  row, so the caller cannot supply a contradictory pair.
- **Does the database prevent it? No.** One foreign key checks the code exists
  and the other checks the id exists, and nothing ties the two together. Any
  writer that bypasses the script can store a contradiction. A composite foreign
  key from `(product_id, product_code)` to products would close this; it was not
  added because the old column is removed at the end anyway.

## Step 5: backfill (`031_backfill_ticket_product.sql`)

```
run 1:            UPDATE 6
run 2:            UPDATE 0     <- safe to rerun, nothing left to change
old_writer.sql:   INSERT 0 1   <- a new old-style ticket with no product_id
run 3:            UPDATE 1     <- picks up exactly that ticket
verify.sql:       (0 rows)
```

`verify.sql` lists any ticket whose `product_id` is missing, points at no
product, or disagrees with its `product_code`; zero rows means the data is
consistent. The script is rerunnable because of `where t.product_id is null`.
Comparison against `baseline_before.txt`: `TICKET-1`, `TICKET-2` and `TICKET-3`
have the same product codes, prices and currencies as before. The other tickets
in the table were created during the exercise.

## Step 6: make `product_id` required (`032_require_ticket_product_id.sql`)

Deliberately created a ticket with no `product_id` (old writer), then ran the
migration:

```
BEGIN
SET
ALTER TABLE
ERROR:  column "product_id" of relation "tickets" contains null values
```

The foreign key validation passed (empty values are allowed there) and
`set not null` refused. psql was run with `ON_ERROR_STOP=1`, so it stopped at the
error and the connection closed; because the migration is one transaction, the
validation step was rolled back with it and nothing was left half applied. After running the backfill again and `verify.sql`
(`UPDATE 1`, zero rows), the same file ran to `COMMIT`. An insert that only
provides `product_code` is now rejected:

```
ERROR:  null value in column "product_id" of relation "tickets" violates not-null constraint
```

## Step 7: contract

Order used, and why:

1. **Allow `product_code` to be empty** (`033_relax_ticket_product_code.sql`).
   The lecture 2 migration made it `not null`, so a writer that no longer sets it
   would be rejected.
2. **Switch writer and reader to `product_id` only.** The new writer no longer
   writes `product_code`; the new reader joins products through `product_id`. A
   ticket inserted this way has an empty `product_code` and a valid `product_id`.
3. **Check what depends on the column** (`dependencies.sql`) before dropping.
4. **Drop it** (`034_drop_ticket_product_code.sql`), without `CASCADE`.

What depends on `tickets.product_code`:

| Kind | Found |
|---|---|
| Constraints | `tickets_product_fk` (foreign key to `products(code)`) and `NOT NULL` |
| Indexes, views, materialized views, functions, triggers | none |
| SQL files in the repo | seed files (`010`, `011`), the lecture 2 migration `011_ticketing_integrity.sql`, `constraint_test.sql` (12 mentions), `limits_demo.sql`, `constraints_should_fail.sql`, and the lecture 4 scripts themselves |

PostgreSQL only reports the first row of that table. The SQL files were found by
searching the repo, which is the part the database cannot tell you. The drop
migration removes the foreign key explicitly, so nothing is deleted silently:

```sql
alter table tickets drop constraint tickets_product_fk;
alter table tickets drop column product_code;
```

Result: `tickets` has no `product_code`, `product_id` is `uuid not null` with a
foreign key to `products(id)`, and the old reader now fails:

```
ERROR:  column "product_code" does not exist
HINT:  Perhaps you meant to reference the column "tickets.product_id".
```

**Known breakage left behind.** Scripts that insert tickets with `product_code`
(the lecture 2 tests `constraint_test.sql` and `limits_demo.sql`, and the
`old_*`, `baseline` and `mismatch` scripts) fail from here on. The lecture 4
scripts are kept as evidence of the old behaviour and are not meant to be rerun.
The lecture 2 tests need updating to use `product_id`.

## Step 8: what a migration tool produces

The repo has no EF Core project, so this is the brief's fallback: an AI-drafted
EF Core migration, compared with the SQL above. **This draft was not compiled or
run, and not generated from a real model.** It shows what EF Core typically
produces when a property is replaced: `ProductCode` (string) becomes `ProductId`
(`Guid`, required).

What EF Core's scaffolding typically emits:

```csharp
migrationBuilder.DropForeignKey(name: "tickets_product_fk", table: "tickets");
migrationBuilder.DropColumn(name: "product_code", table: "tickets");

migrationBuilder.AddColumn<Guid>(
    name: "product_id", table: "tickets", type: "uuid", nullable: false,
    defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

migrationBuilder.CreateIndex(name: "ix_tickets_product_id", table: "tickets", column: "product_id");

migrationBuilder.AddForeignKey(
    name: "fk_tickets_products_product_id", table: "tickets", column: "product_id",
    principalTable: "products", principalColumn: "id", onDelete: ReferentialAction.Cascade);
```

What goes wrong if it is applied to a populated database:

- It drops `product_code` **before** anything is copied, so the data that says
  which product each ticket belongs to is destroyed. (If EF treats the change as a
  rename, it can emit a rename instead, but that only works when the types match;
  string to uuid is a different column.)
- The new column gets the all-zero uuid as its default, so every existing ticket
  points at a product id that does not exist, and the foreign key fails (or, if
  it is created `not valid`, the data is silently wrong).
- It never fills in `products.id`, and cannot know how to map old codes to new
  ids.

What has to be written by hand to make it safe, in this order:

```csharp
// 1. expand: nullable column, not valid FK
migrationBuilder.AddColumn<Guid>("product_id", "tickets", "uuid", nullable: true);
migrationBuilder.Sql("alter table tickets add constraint tickets_product_id_fk " +
    "foreign key (product_id) references products(id) not valid;");

// 2. backfill: a data change the tool cannot infer
migrationBuilder.Sql(@"update tickets t set product_id = p.id
                       from products p
                       where t.product_id is null and p.code = t.product_code;");

// 3. verify, then require it (a later migration, after code has switched)
migrationBuilder.Sql("alter table tickets validate constraint tickets_product_id_fk;");
migrationBuilder.AlterColumn<Guid>("product_id", "tickets", nullable: false);

// 4. contract (a later migration, once nothing reads the old column)
migrationBuilder.DropColumn("product_code", "tickets");
```

**Which parts can the tool work out, and which need you?** From the model alone
the tool can work out the end state of the schema: the new column, its type, the
foreign key and the index, and the order to drop the old ones. It cannot work out
anything that depends on the existing data or on time. That means copying the
data (it does not know that `product_code` maps to `products.code` and then to
`products.id`), the order (copy before drop), the pause between steps while old
and new code both run, and the safety settings such as `not valid`, `validate`
and `lock_timeout`. It also cannot see anything outside the model, such as the
tests and SQL files that still use `product_code`. A model diff describes where
you end up; a safe migration describes how to get there while the system keeps
running.

## Issue and decision

**Issue found.** After the migration the database accepts a ticket whose
`product_code` and `product_id` disagree (Step 4). Only the writer script
prevented it. This is the same kind of gap as the lecture 2 findings: a rule
enforced only in application code. It is harmless here because the old column is
dropped at the end, but a longer migration window would need a composite foreign
key.

**Decision.** Expand, backfill, verify, require, then contract, with each step
as its own migration file (`030` to `034`), instead of one migration that does
everything. Alternatives rejected: the one-step migration from Step 2 (data loss
and immediate failure), and keeping `product_code` indefinitely as a second
reference (two sources of truth that can disagree). Consequence: five migrations
instead of one, and a window in which both columns exist; in return every step
can be checked, a failed step leaves nothing half applied, and old code keeps
working until the contract step.

## Submission checklist

- [x] Baseline with at least two products, three tickets, more than one product
- [x] Bad migration tried and the errors saved
- [x] Expand migration (`030`) applied once
- [x] Old and new writers and readers tested, mismatch behaviour recorded
- [x] Backfill (`031`) run twice, second run changed nothing, verify returned zero rows
- [x] Required `product_id` (`032`), failure shown first, then success
- [x] Contract (`033`, `034`) with dependency check and no `CASCADE`
- [x] EF Core comparison (draft, not compiled)
- [ ] Update the lecture 2 tests that still insert `product_code`
- [ ] Remove the duplicate `031_backfill_tickets_product.sql` (plural) if still present
- [ ] Commit on the lecture 4 branch and push to the group repo
