# MobilityTicketing: Lecture 1 starter

This repository is the starter code for the first lecture. It contains a small PostgreSQL slice for route maintenance and timetable queries.

The exercise is intentionally incomplete. Add the route-stop key, complete the seed data, write the three workload queries, and follow the lab brief in `docs/lab.md`.

## Start the database

Requirements:

- Docker Desktop with Compose

Start PostgreSQL:

```bash
docker compose up -d
```

The database is available at `localhost:5432` with database `mobility`, user `mobility`, and password `mobility`.

To stop it:

```bash
docker compose down
```

The starter seed loads operators, routes, and stops. Complete `database/postgres/002_seed.sql` with route-stop rows and trips after deciding on the route-stop primary key. The initialization scripts run only when PostgreSQL starts with an empty data directory, so rebuild the container when you need to replay them:

```bash
docker compose down -v
docker compose up -d
```

## Your tasks

1. Add primary-key and foreign-key relationships where needed.
2. Decide whether a route may visit the same stop more than once, and explain the choice.
3. Add at least two trips per route on the same service date.
4. Complete the three query skeletons.
5. Compare the SQL model with your ER diagram.
6. Record one assumption that may change later in `docs/notes.md`.

Do not add MongoDB, Redis, queues, payment logic, validation logic, reporting tables, or performance indexes in this first slice.

## Files

- `compose.yaml`: PostgreSQL starter infrastructure.
- `database/postgres/001_relational_baseline.sql`: incomplete relational schema.
- `database/postgres/002_seed.sql`: repeatable starter seed with TODOs.
- `database/postgres/003_queries.sql.example`: query skeleton for the three released workloads.
- `docs/lab.md`: student-facing lab brief and submission checklist.

The sample solution is intentionally not included in this repository.
