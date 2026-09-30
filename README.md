# Containerized Business Analytics System — Project Monitoring API

Backend API for managing and analysing project data (projects, tasks, users, departments),
built with **.NET 8 (Clean Architecture)** on **PostgreSQL 16**, fully containerised with
**Docker Compose**, plus **Bash scripts** for backup, health checks, resource monitoring and log rotation.

---

## Quick start (one command)

Requirements: Docker Engine 24+ with Compose v2 (Docker Desktop is fine). Nothing else — .NET is not needed on the host.

```bash
git clone https://github.com/noppornnakub1/project-monitoring.git && cd project-monitoring
docker compose up -d --build
```

On first start PostgreSQL runs `db/init/01-schema.sql`, `02-procedures.sql` and `03-seed.sql` automatically, and the API waits until the DB is healthy.

| URL | |
|---|---|
| http://localhost:8080/swagger | Swagger UI (interactive API docs) |
| http://localhost:8080/health  | health endpoint (checks DB connectivity) |
| `localhost:5432`              | PostgreSQL (`postgres` / `postgres`, db `project_monitoring`) |

Verify:

```bash
./scripts/healthcheck.sh -w 60
curl -s http://localhost:8080/api/reports/department-progress
```

Configuration is optional: copy `.env.example` to `.env` to change ports / credentials.

To re-run the init scripts from scratch (**deletes all data**): `docker compose down -v && docker compose up -d`.

---

## Architecture

```
src/
├── ProjectMonitoring.Domain          Entities + allowed status/priority/role values. No dependencies.
├── ProjectMonitoring.Application     Use cases (services + business rules), DTOs, validation, repository
│                                      interfaces, application exceptions. Depends on Domain only.
├── ProjectMonitoring.Infrastructure  Data access with Dapper + Npgsql: repositories that call stored procedures /
│                                      functions by name. Implements Application interfaces.
└── ProjectMonitoring.Api             Controllers, global exception handler (ProblemDetails), health checks, Swagger.
```

Dependency direction: `Api → Infrastructure → Application → Domain`.

### Data access: stored procedures + Dapper

**All SQL lives in the database** (`db/init/02-procedures.sql`); the C# code contains no queries, it only calls
procedures/functions by name through Dapper:

```csharp
db.CallProcedureAsync<int>("sp_project_create", new { p.DepartmentId, p.Name, ... }, "p_id", ct);
db.QueryFunctionSingleAsync<ProjectDto>("fn_project_get", new { Id = id }, ct);
```

| Prefix | Kind | Used for | Called with |
|---|---|---|---|
| `sp_*` | `PROCEDURE` | create / update / delete; results via `INOUT p_id` / `p_found` | `CALL sp_x(...)` |
| `fn_*` | `FUNCTION` | list / get / lookups / reports | `SELECT * FROM fn_x(...)` |
| `v_*`  | `VIEW` | shared row shapes reused by the list/get functions | |

PostgreSQL procedures cannot return result sets, so every read is a function.
Arguments are passed by **named notation** (`p_department_id => @DepartmentId`), generated from the argument object
in `StoredProcedureExtensions`, so parameter order can't be mixed up and all values are sent as parameters.
Paged list functions return the total count together with the page in one call.
Business rules and validation stay in the Application services.

### Error handling

All errors are returned as RFC 7807 `application/problem+json`:

| Situation | Status |
|---|---|
| Invalid body / query (DataAnnotations, `[ApiController]`) | 400 with per-field `errors` |
| Business rule (e.g. referenced department doesn't exist, end date before start) | 400 |
| Entity not found | 404 |
| Duplicate email, department still in use | 409 |
| PostgreSQL constraint violation that slipped past validation (unique / FK / check) | 409 / 400 |
| Anything else | 500 — details logged, never leaked to the client |

---

## Database design

```
departments 1───* users
departments 1───* projects *───1 users (owner, nullable)
projects    1───* tasks    *───1 users (assignee, nullable)
system_logs *───1 users (nullable)            ← filled automatically by audit triggers
```

| Table | Notes |
|---|---|
| `departments` | unique name |
| `users` | FK → departments (`RESTRICT`), case-insensitive unique email (`UNIQUE INDEX … (lower(email))`), role `CHECK`, email regex `CHECK` |
| `projects` | FK → departments (`RESTRICT`), owner FK → users (`SET NULL`), status `CHECK`, `end_date >= start_date` `CHECK` |
| `tasks` | FK → projects (`CASCADE`), assignee FK → users (`SET NULL`), status/priority `CHECK`, `progress` 0–100 `CHECK` |
| `system_logs` | append-only audit log with `jsonb` payload (old/new row) |

### Why a fifth table (`departments`)?

The brief lists four tables (`projects`, `tasks`, `users`, `system_logs`) but also asks for a report of
**task progress per department** — and none of those four tables has anywhere to store a department.

A plain `department varchar` column on `users`/`projects` would work, but it is not normalised:
"Engineering" and "engineering " would silently become two departments in the report, and renaming a
department would mean updating every row. A separate `departments` table referenced by foreign keys keeps
department names unique (`uq_departments_name`), lets the database reject unknown departments, and makes a
rename a one-row change. The four required tables are unchanged apart from the `department_id` foreign key.

PostgreSQL features used:

- **Identity columns** (`GENERATED ALWAYS AS IDENTITY`) instead of `serial`.
- **Indexes**: every FK is indexed; composite `tasks(project_id, status)`; **partial index** `tasks(due_date) WHERE status <> 'done'` for overdue queries; **expression index** on `lower(email)`; **BRIN** on `system_logs.created_at` (cheap for append-only time series); **GIN** (`jsonb_path_ops`) on `system_logs.context`.
- **Triggers (PL/pgSQL)**: `updated_at` maintenance; tasks status ↔ progress/`completed_at` consistency (`done` ⇒ progress 100); generic **audit trigger** writing every INSERT/UPDATE/DELETE on projects/tasks into `system_logs` as JSONB.
- **Stored procedures** (`PL/pgSQL`, `INOUT` output parameters) for all writes, and **functions** for all reads.
- **Report functions** (`LANGUAGE sql STABLE`, `RETURNS TABLE`, optional parameters):
  `fn_report_department_progress(p_department_id)` (CTEs, `LEFT JOIN`, `count(*) FILTER (WHERE …)`, `avg`, `dense_rank()` window function),
  `fn_report_project_progress(p_department_id, p_status)`, `fn_report_user_workload(p_department_id)`.
  They can also be run directly, e.g. `SELECT * FROM fn_report_department_progress();`

---

## API reference

Base URL `http://localhost:8080`. Full schema and "try it out" in Swagger UI. List endpoints are paginated:
`?page=1&pageSize=20` → `{ items, page, pageSize, totalCount, totalPages }`.

### CRUD

| Method | Path | Query filters |
|---|---|---|
| GET / POST | `/api/departments` | |
| GET / PUT / DELETE | `/api/departments/{id}` | |
| GET / POST | `/api/users` | `departmentId`, `isActive`, `search` |
| GET / PUT / DELETE | `/api/users/{id}` | |
| GET / POST | `/api/projects` | `departmentId`, `status`, `search` |
| GET / PUT / DELETE | `/api/projects/{id}` | |
| GET / POST | `/api/tasks` | `projectId`, `assigneeId`, `status`, `priority`, `overdue=true` |
| GET / PUT / DELETE | `/api/tasks/{id}` | |
| GET | `/api/system-logs` | `source` (`projects`/`tasks`), `action`, `entityId`, `level`, `from`, `to` |

Allowed values — project `status`: `planning | active | on_hold | completed | cancelled`;
task `status`: `todo | in_progress | review | done`; `priority`: `low | medium | high | critical`;
user `role`: `admin | manager | member`.

Examples:

```bash
# create a project
curl -s -X POST http://localhost:8080/api/projects -H 'Content-Type: application/json' -d '{
  "name": "Data Warehouse", "description": "Central reporting DB", "status": "active",
  "departmentId": 1, "ownerId": 1, "startDate": "2026-10-01", "endDate": "2026-12-31" }'

# create a task
curl -s -X POST http://localhost:8080/api/tasks -H 'Content-Type: application/json' -d '{
  "projectId": 1, "assigneeId": 2, "title": "Design star schema",
  "status": "in_progress", "priority": "high", "progress": 30, "dueDate": "2026-10-15" }'

# overdue tasks
curl -s 'http://localhost:8080/api/tasks?overdue=true'

# audit trail of task 1
curl -s 'http://localhost:8080/api/system-logs?source=tasks&entityId=1'
```

Validation error example:

```json
{
  "type": "https://tools.ietf.org/html/rfc9110#section-15.5.1",
  "title": "One or more validation errors occurred.",
  "status": 400,
  "errors": { "Progress": ["The field Progress must be between 0 and 100."] }
}
```

### Reports & export

Every report accepts `?format=json` (default) or `?format=csv` (downloads a UTF-8 CSV file).

| Path | Description |
|---|---|
| `GET /api/reports/department-progress?departmentId=` | Per department: projects (total/active/completed), tasks (total/done/in progress/overdue), **completion rate %**, **average task progress %**, rank |
| `GET /api/reports/project-progress?departmentId=&status=` | Per project: task counts, overdue, average progress, `isLate`; late projects first |
| `GET /api/reports/user-workload?departmentId=` | Per active user: open, critical open, overdue, done in last 30 days |

```bash
curl -s http://localhost:8080/api/reports/department-progress
curl -OJ 'http://localhost:8080/api/reports/department-progress?format=csv'
```

```json
{
  "generatedAt": "2026-09-29T11:00:00Z",
  "count": 4,
  "data": [
    { "departmentId": 3, "departmentName": "Finance", "totalProjects": 1, "activeProjects": 0,
      "completedProjects": 1, "totalTasks": 2, "doneTasks": 2, "inProgressTasks": 0,
      "overdueTasks": 0, "completionRate": 100.00, "avgProgress": 100.00, "progressRank": 1 }
  ]
}
```

---

## Docker setup

| | |
|---|---|
| `Dockerfile` | Multi-stage: `sdk:8.0` restores (cached layer) and publishes → `aspnet:8.0` runtime only. Runs as non-root `app` user, `HEALTHCHECK` on `/health`. |
| `db` service | `postgres:16`, named volume `pgdata` for data, `./db/init` mounted read-only into `/docker-entrypoint-initdb.d`, `./backups` → `/backups`, `./scripts` → `/scripts:ro`, `pg_isready` healthcheck. |
| `api` service | `depends_on: db: condition: service_healthy`, connection string points to host `db` (Compose DNS). |
| Network | user-defined bridge `backend`; containers talk by service name. |
| Limits | CPU / memory limits per service (`deploy.resources.limits`). |
| Logging | `json-file` driver capped at `10m × 3` per container, so stdout logs can't fill the disk. |

---

## Linux / ops scripts (`scripts/`)

All scripts are Bash (compatible with bash 3.2 on macOS and Linux), use `set -Eeuo pipefail`, support `-h`, and return non-zero exit codes on failure so they can be chained in cron / CI.

| Script | What it does |
|---|---|
| `backup.sh` | `pg_dump` → `gzip -9` → integrity check (`gzip -t` + dump-complete marker) → atomic rename → deletes backups older than *N* days. Runs **from the host** (via `docker compose exec`) **or inside the container**. |
| `restore.sh` | Restores the newest (or given) backup, with confirmation prompt. |
| `healthcheck.sh` | Container state, Docker health status, restart count, `pg_isready`, `GET /health`. `-w 60` waits for the stack to become healthy. |
| `monitor.sh` | CPU / memory / net / block I/O / PIDs via `docker stats`, alerts over thresholds, DB volume size and host disk free. `-w 5` watch mode, `-l` logs to `logs/monitor.csv`. |
| `log-rotate.sh` | Collects container logs into `logs/*.log` (`-c`, incremental), rotates files over a size limit to `.1.gz … .N.gz` using copy-truncate, keeps *N*, lock against concurrent runs. `-g 12M` generates a big dummy log to demonstrate. |

```bash
# Backup - from host
./scripts/backup.sh                 # keep 7 days (default)
./scripts/backup.sh -k 14           # keep 14 days

# Backup - from inside the db container
docker compose exec db bash /scripts/backup.sh

# Restore latest backup
./scripts/restore.sh

# Health
./scripts/healthcheck.sh

# Resource usage (single shot / watch every 5 s with CSV log / custom thresholds)
./scripts/monitor.sh
./scripts/monitor.sh -w 5 -l
./scripts/monitor.sh -c 50 -m 70

# Log rotation demo: create a 12 MB log and rotate at 5 MB, keep 3
./scripts/log-rotate.sh -g 12M -s 5M -k 3
# Real use: collect container logs and rotate
./scripts/log-rotate.sh -c
```

Suggested crontab:

```cron
0 2 * * *    /opt/project-monitoring/scripts/backup.sh     >> /var/log/pm-backup.log 2>&1
*/5 * * * *  /opt/project-monitoring/scripts/healthcheck.sh >> /var/log/pm-health.log 2>&1
*/15 * * * * /opt/project-monitoring/scripts/log-rotate.sh -c >> /var/log/pm-logrotate.log 2>&1
```

---

## Running the API without Docker (development)

```bash
docker compose up -d db
dotnet run --project src/ProjectMonitoring.Api --urls http://localhost:5080
```

The default connection string in `appsettings.json` points at `localhost:5432`.
