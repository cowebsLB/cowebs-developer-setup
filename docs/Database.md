# Database

This project has no application database or database schema.

The Backend profile can install PostgreSQL 18 and DBeaver. The optional `backend-databases` pack adds Redis Insight, MongoDB Compass, and MySQL Workbench. Database initialization, credentials, ports, services, and project schemas are intentionally left to the user and are never stored by the setup script.

The v6.3.0-rc.1 preview execution-state implementation uses an append-only, strictly decoded JSONL event journal plus a flushed atomic snapshot, not a database. Resume binds that state to its exact plan, catalog, platform, architecture, profile, and operation inventory. Journals and snapshots remain local to the initiating user and contain redacted structured state rather than credentials or raw package-manager output. A database will be reconsidered only if concurrent sessions, query requirements, or state volume justify its migration and locking cost.
