-- =====================================================================
-- Project Monitoring - schema
-- Executed automatically by the postgres image on first start
-- (/docker-entrypoint-initdb.d), i.e. only when the data volume is empty.
-- =====================================================================
BEGIN;

-- ---------------------------------------------------------------------
-- Shared trigger function: keep updated_at current on every UPDATE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- departments
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        varchar(100) NOT NULL,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_departments_name UNIQUE (name)
);

-- ---------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id  integer      NOT NULL REFERENCES departments (id) ON DELETE RESTRICT,
    full_name      varchar(150) NOT NULL,
    email          varchar(255) NOT NULL,
    role           varchar(20)  NOT NULL DEFAULT 'member',
    is_active      boolean      NOT NULL DEFAULT true,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_users_role  CHECK (role IN ('admin', 'manager', 'member')),
    CONSTRAINT ck_users_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
-- Case-insensitive uniqueness on email (expression index)
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));
CREATE INDEX ix_users_department_id ON users (department_id);

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------
CREATE TABLE projects (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id  integer      NOT NULL REFERENCES departments (id) ON DELETE RESTRICT,
    owner_id       integer      REFERENCES users (id) ON DELETE SET NULL,
    name           varchar(200) NOT NULL,
    description    text,
    status         varchar(20)  NOT NULL DEFAULT 'planning',
    start_date     date,
    end_date       date,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_projects_status CHECK (status IN ('planning', 'active', 'on_hold', 'completed', 'cancelled')),
    CONSTRAINT ck_projects_dates  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);
CREATE INDEX ix_projects_department_id ON projects (department_id);
CREATE INDEX ix_projects_owner_id      ON projects (owner_id);
CREATE INDEX ix_projects_status        ON projects (status);

CREATE TRIGGER trg_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- tasks
-- ---------------------------------------------------------------------
CREATE TABLE tasks (
    id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id    integer      NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    assignee_id   integer      REFERENCES users (id) ON DELETE SET NULL,
    title         varchar(200) NOT NULL,
    description   text,
    status        varchar(20)  NOT NULL DEFAULT 'todo',
    priority      varchar(10)  NOT NULL DEFAULT 'medium',
    progress      smallint     NOT NULL DEFAULT 0,
    due_date      date,
    completed_at  timestamptz,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_tasks_status   CHECK (status IN ('todo', 'in_progress', 'review', 'done')),
    CONSTRAINT ck_tasks_priority CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    CONSTRAINT ck_tasks_progress CHECK (progress BETWEEN 0 AND 100)
);
-- Composite index serves "tasks of project X (by status)" and the FK lookup
CREATE INDEX ix_tasks_project_status ON tasks (project_id, status);
CREATE INDEX ix_tasks_assignee_id    ON tasks (assignee_id);
-- Partial index: only open tasks matter for overdue queries
CREATE INDEX ix_tasks_open_due_date  ON tasks (due_date) WHERE status <> 'done';

-- Keep status / progress / completed_at consistent
CREATE OR REPLACE FUNCTION tasks_sync_completion() RETURNS trigger AS $$
BEGIN
    IF NEW.status = 'done' THEN
        NEW.progress     := 100;
        NEW.completed_at := COALESCE(NEW.completed_at, now());
    ELSE
        NEW.completed_at := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tasks_sync_completion BEFORE INSERT OR UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION tasks_sync_completion();
CREATE TRIGGER trg_tasks_updated_at BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- system_logs (append-only audit / event log)
-- ---------------------------------------------------------------------
CREATE TABLE system_logs (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    level       varchar(10)  NOT NULL DEFAULT 'info',
    source      varchar(100) NOT NULL,
    action      varchar(20)  NOT NULL,
    entity_id   integer,
    message     text         NOT NULL,
    context     jsonb        NOT NULL DEFAULT '{}'::jsonb,
    user_id     integer      REFERENCES users (id) ON DELETE SET NULL,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_system_logs_level CHECK (level IN ('debug', 'info', 'warning', 'error'))
);
-- BRIN: tiny index, ideal for append-only time-ordered data
CREATE INDEX ix_system_logs_created_at_brin ON system_logs USING brin (created_at);
CREATE INDEX ix_system_logs_source_entity   ON system_logs (source, entity_id);
-- GIN: fast containment queries on the JSONB payload (context @> '{...}')
CREATE INDEX ix_system_logs_context_gin     ON system_logs USING gin (context jsonb_path_ops);

-- Generic audit trigger: every change on projects/tasks is recorded with
-- the before/after row as JSONB.
CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger AS $$
DECLARE
    v_id integer;
BEGIN
    v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
    INSERT INTO system_logs (level, source, action, entity_id, message, context)
    VALUES (
        'info',
        TG_TABLE_NAME,
        lower(TG_OP),
        v_id,
        format('%s %s id=%s', TG_TABLE_NAME, lower(TG_OP), v_id),
        jsonb_strip_nulls(jsonb_build_object(
            'old', CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
            'new', CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END))
    );
    RETURN NULL; -- AFTER trigger: return value ignored
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_projects_audit AFTER INSERT OR UPDATE OR DELETE ON projects
    FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER trg_tasks_audit AFTER INSERT OR UPDATE OR DELETE ON tasks
    FOR EACH ROW EXECUTE FUNCTION audit_row_change();

COMMIT;
