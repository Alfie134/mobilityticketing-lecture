# Lecture 1 implementation lab

## Purpose

Build the smallest relational model that supports route maintenance and upcoming-trip queries. The implementation is not expected to represent the complete MobilityTicketing platform. It should make your modelling assumptions executable.

## Work in this lecture

1. Create tables for operators, routes, stops, route stops, and trips.
2. Decide the primary key of the route-stop relation and explain the decision.
3. Add primary-key and foreign-key relationships.
4. Insert the supplied seed data.
5. Write the three workload queries in `database/postgres/003_queries.sql.example`.
6. Compare the implemented schema with your ER diagram and record any difference.

## Workload queries

1. Show the next 20 scheduled trips for a route after a supplied timestamp.
2. Show the ordered stops belonging to a route.
3. Show all routes and the number of scheduled trips on a supplied service date, including routes with no trips.

## Do not implement yet

Do not add MongoDB, Redis, caching, event queues, payment logic, validation logic, reporting tables, or performance indexes. Those decisions are introduced later.

## Required evidence

- A schema that can be recreated from an empty database.
- Seed data that can be loaded more than once without manual editing.
- The three queries and representative results.
- A short note identifying one modelling assumption that may change later.
- A system context, access-pattern map, ER diagram, and one functional dependency note.

## Submission checklist

- [ ] Describe the customers, operators, and city transport context without naming a database product.
- [ ] Cover route search, ticket purchase, ticket validation, timetable updates, real-time availability, and reporting in the access-pattern map.
- [ ] Include identifiers, relationships, and cardinalities in the ER diagram.
- [ ] Explain one functional dependency and what normalization prevents.
- [ ] State what the implementation proves and what remains unknown.
- [ ] Commit the implementation under `database/postgres/`.
