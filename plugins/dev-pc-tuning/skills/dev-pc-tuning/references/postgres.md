# PostgreSQL for test suites

Suites that create databases, run migrations and write fixtures spend much of their time
waiting on the database's disk flushes. A **throwaway test cluster** doesn't need crash
safety, and PostgreSQL documents settings for exactly that case ("Non-Durable Settings" in
the PostgreSQL manual).

First, measure: time a full run, and check whether `postgres.exe` shows high disk activity
in Resource Monitor (`resmon`) during it.

## Separate the test cluster from data you care about

Everything below makes a crash or power loss able to **corrupt the whole cluster**, not just
lose recent writes. Apply it only to a cluster (or container) that holds nothing but test
data and can be recreated from scripts. If the same local server also holds development
data the user wants to keep, run a second instance for tests instead:

```powershell
# a disposable container (Docker or Podman), data inside the container, on a separate port
docker run -d --name pg-test -p 55432:5432 -e POSTGRES_PASSWORD=<choose-one> postgres:17 `
  -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=300
# undo: docker rm -f pg-test
```

## Non-durable settings (measure first)

On an existing test-only cluster, as a superuser (`psql`):

```sql
ALTER SYSTEM SET fsync = off;
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET full_page_writes = off;
SELECT pg_reload_conf();          -- these three take effect without a restart
-- undo:
ALTER SYSTEM RESET fsync; ALTER SYSTEM RESET synchronous_commit;
ALTER SYSTEM RESET full_page_writes; SELECT pg_reload_conf();
```

- **Gain:** large for write-heavy suites (many small transactions, `CREATE DATABASE`,
  migrations); small for read-heavy ones. Compare full-run times.
- **Risk:** after a crash or power cut, the cluster may be unrecoverable - drop and recreate
  it. Never on a cluster with data you want to keep.
- `synchronous_commit = off` alone is the mild version: a crash loses the last fraction of a
  second of commits but doesn't corrupt anything. It can also be set per test connection
  (`SET synchronous_commit = off`) without touching the server.
- Put the test cluster's data folder on the Dev Drive (initialise it there with `initdb -D`,
  or mount a container volume from there). RAM disks on Windows need third-party drivers;
  not worth the added risk.

## Template databases instead of re-running migrations

If each test (or test file) creates a fresh database and runs all migrations, create one
fully migrated database once and clone it:

```sql
CREATE DATABASE app_template;                -- run migrations + seed into it once
CREATE DATABASE test_1234 TEMPLATE app_template;
```

- **Gain:** cloning takes milliseconds to a few seconds; running migrations can take far
  longer. Often the single biggest win for database-heavy suites.
- **Catches:** nobody may be connected to the template while it is cloned (close the
  migration connection; tests must never connect to it). Rebuild it when migrations change
  (e.g. name it after a hash of the migrations folder). On PostgreSQL 15+, try
  `STRATEGY = FILE_COPY` vs the default `WAL_LOG` for large templates and keep the faster.
- Drop test databases at the end of the run (or at the start of the next one).

## Parallel runs

- Raise `max_connections` on the test cluster if parallel tests open pools (each pool x
  threads); "too many clients" errors look like flaky tests.
- Give each run its own database names (prefix with a run id) so two runs can't drop each
  other's fixtures (`test-runs.md`).
