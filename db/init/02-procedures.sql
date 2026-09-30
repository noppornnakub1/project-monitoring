-- =====================================================================
-- Project Monitoring - stored procedures & functions
-- All data access used by the API lives here; the C# code only calls these by name.
--
--   sp_*  PROCEDURE  writes (create / update / delete), called with CALL.
--                    Results come back through INOUT parameters (p_id, p_found).
--   fn_*  FUNCTION   reads (list / get / lookups / reports), called with SELECT.
--                    PostgreSQL procedures cannot return result sets, so reads
--                    must be functions.
--   v_*   VIEW       shared "detail" row shapes, reused by the list/get functions.
--
-- Paged list functions return (total_count, item) where item is a row of the
-- matching v_*_detail view. When the page is past the end, a single row with
-- the total and item = NULL is returned, so the total is always known.
-- =====================================================================
BEGIN;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

-- '%term%' for ILIKE with the user's own % and _ escaped. NULL/blank -> NULL (no filter).
CREATE OR REPLACE FUNCTION fn_like_pattern(p_term text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN btrim(p_term) = '' THEN NULL
                ELSE '%' || replace(replace(replace(btrim(p_term), '\', '\\'), '%', '\%'), '_', '\_') || '%'
           END;
$$;

-- =====================================================================
-- Departments
-- =====================================================================
CREATE VIEW v_department_detail AS
SELECT d.id, d.name, d.created_at,
       (SELECT count(*) FROM users u    WHERE u.department_id = d.id)::int AS user_count,
       (SELECT count(*) FROM projects p WHERE p.department_id = d.id)::int AS project_count
FROM departments d;

CREATE OR REPLACE FUNCTION fn_department_list() RETURNS SETOF v_department_detail
LANGUAGE sql STABLE AS $$
    SELECT * FROM v_department_detail ORDER BY name;
$$;

CREATE OR REPLACE FUNCTION fn_department_get(p_id integer) RETURNS SETOF v_department_detail
LANGUAGE sql STABLE AS $$
    SELECT * FROM v_department_detail WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION fn_department_exists(p_id integer) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM departments WHERE id = p_id);
$$;

-- True when users or projects still reference the department
CREATE OR REPLACE FUNCTION fn_department_in_use(p_id integer) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM users    WHERE department_id = p_id)
        OR EXISTS (SELECT 1 FROM projects WHERE department_id = p_id);
$$;

CREATE OR REPLACE PROCEDURE sp_department_create(p_name varchar, INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO departments (name) VALUES (p_name) RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_department_update(p_id integer, p_name varchar, INOUT p_found boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE departments SET name = p_name WHERE id = p_id;
    p_found := FOUND;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_department_delete(p_id integer, INOUT p_found boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM departments WHERE id = p_id;
    p_found := FOUND;
END;
$$;

-- =====================================================================
-- Users
-- =====================================================================
CREATE VIEW v_user_detail AS
SELECT u.id, u.full_name, u.email, u.role, u.is_active,
       u.department_id, d.name AS department_name, u.created_at, u.updated_at
FROM users u
JOIN departments d ON d.id = u.department_id;

CREATE OR REPLACE FUNCTION fn_user_list(
    p_department_id integer DEFAULT NULL,
    p_is_active     boolean DEFAULT NULL,
    p_search        text    DEFAULT NULL,   -- name or email, case-insensitive
    p_limit         integer DEFAULT 20,
    p_offset        integer DEFAULT 0)
RETURNS TABLE (total_count integer, item v_user_detail)
LANGUAGE sql STABLE AS $$
    WITH filtered AS (
        SELECT v AS item
        FROM v_user_detail v
        WHERE (p_department_id IS NULL OR v.department_id = p_department_id)
          AND (p_is_active IS NULL OR v.is_active = p_is_active)
          AND (fn_like_pattern(p_search) IS NULL
               OR v.full_name ILIKE fn_like_pattern(p_search)
               OR v.email     ILIKE fn_like_pattern(p_search))
    ), page AS (
        SELECT item, row_number() OVER (ORDER BY (item).id) AS rn
        FROM filtered
        ORDER BY rn
        LIMIT p_limit OFFSET p_offset
    )
    SELECT (SELECT count(*) FROM filtered)::int, page.item
    FROM (SELECT 1) one
    LEFT JOIN page ON true
    ORDER BY page.rn;
$$;

CREATE OR REPLACE FUNCTION fn_user_get(p_id integer) RETURNS SETOF v_user_detail
LANGUAGE sql STABLE AS $$
    SELECT * FROM v_user_detail WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION fn_user_exists_active(p_id integer) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM users WHERE id = p_id AND is_active);
$$;

-- lower(email) matches the uq_users_email_lower expression index
CREATE OR REPLACE FUNCTION fn_user_email_taken(p_email text, p_exclude_id integer DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM users
        WHERE lower(email) = lower(p_email)
          AND (p_exclude_id IS NULL OR id <> p_exclude_id));
$$;

CREATE OR REPLACE PROCEDURE sp_user_create(
    p_department_id integer,
    p_full_name     varchar,
    p_email         varchar,
    p_role          varchar,
    p_is_active     boolean,
    INOUT p_id      integer DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO users (department_id, full_name, email, role, is_active)
    VALUES (p_department_id, p_full_name, p_email, p_role, p_is_active)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_user_update(
    p_id            integer,
    p_department_id integer,
    p_full_name     varchar,
    p_email         varchar,
    p_role          varchar,
    p_is_active     boolean,
    INOUT p_found   boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE users
    SET department_id = p_department_id, full_name = p_full_name, email = p_email,
        role = p_role, is_active = p_is_active
    WHERE id = p_id;
    p_found := FOUND;
END;
$$;

-- FKs are ON DELETE SET NULL: owned projects / assigned tasks become unassigned
CREATE OR REPLACE PROCEDURE sp_user_delete(p_id integer, INOUT p_found boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM users WHERE id = p_id;
    p_found := FOUND;
END;
$$;

-- =====================================================================
-- Projects
-- =====================================================================
CREATE VIEW v_project_detail AS
SELECT p.id, p.name, p.description, p.status, p.start_date, p.end_date,
       p.department_id, d.name AS department_name,
       p.owner_id, u.full_name AS owner_name,
       ts.total_tasks, ts.done_tasks, ts.progress,
       p.created_at, p.updated_at
FROM projects p
JOIN departments d ON d.id = p.department_id
LEFT JOIN users u  ON u.id = p.owner_id
-- LATERAL: per-project task aggregates computed next to each project row
CROSS JOIN LATERAL (
    SELECT count(*)::int                                  AS total_tasks,
           count(*) FILTER (WHERE t.status = 'done')::int AS done_tasks,
           COALESCE(round(avg(t.progress), 2), 0)         AS progress
    FROM tasks t
    WHERE t.project_id = p.id
) ts;

CREATE OR REPLACE FUNCTION fn_project_list(
    p_department_id integer DEFAULT NULL,
    p_status        varchar DEFAULT NULL,
    p_search        text    DEFAULT NULL,   -- project name, case-insensitive
    p_limit         integer DEFAULT 20,
    p_offset        integer DEFAULT 0)
RETURNS TABLE (total_count integer, item v_project_detail)
LANGUAGE sql STABLE AS $$
    WITH filtered AS (
        SELECT v AS item
        FROM v_project_detail v
        WHERE (p_department_id IS NULL OR v.department_id = p_department_id)
          AND (p_status IS NULL OR v.status = p_status)
          AND (fn_like_pattern(p_search) IS NULL OR v.name ILIKE fn_like_pattern(p_search))
    ), page AS (
        SELECT item, row_number() OVER (ORDER BY (item).updated_at DESC, (item).id) AS rn
        FROM filtered
        ORDER BY rn
        LIMIT p_limit OFFSET p_offset
    )
    SELECT (SELECT count(*) FROM filtered)::int, page.item
    FROM (SELECT 1) one
    LEFT JOIN page ON true
    ORDER BY page.rn;
$$;

CREATE OR REPLACE FUNCTION fn_project_get(p_id integer) RETURNS SETOF v_project_detail
LANGUAGE sql STABLE AS $$
    SELECT * FROM v_project_detail WHERE id = p_id;
$$;

-- Current status, NULL when the project does not exist
CREATE OR REPLACE FUNCTION fn_project_status(p_id integer) RETURNS varchar
LANGUAGE sql STABLE AS $$
    SELECT status FROM projects WHERE id = p_id;
$$;

CREATE OR REPLACE PROCEDURE sp_project_create(
    p_department_id integer,
    p_owner_id      integer,
    p_name          varchar,
    p_description   text,
    p_status        varchar,
    p_start_date    date,
    p_end_date      date,
    INOUT p_id      integer DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO projects (department_id, owner_id, name, description, status, start_date, end_date)
    VALUES (p_department_id, p_owner_id, p_name, p_description, p_status, p_start_date, p_end_date)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_project_update(
    p_id            integer,
    p_department_id integer,
    p_owner_id      integer,
    p_name          varchar,
    p_description   text,
    p_status        varchar,
    p_start_date    date,
    p_end_date      date,
    INOUT p_found   boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE projects
    SET department_id = p_department_id, owner_id = p_owner_id, name = p_name,
        description = p_description, status = p_status,
        start_date = p_start_date, end_date = p_end_date
    WHERE id = p_id;
    p_found := FOUND;
END;
$$;

-- Tasks are removed by ON DELETE CASCADE
CREATE OR REPLACE PROCEDURE sp_project_delete(p_id integer, INOUT p_found boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM projects WHERE id = p_id;
    p_found := FOUND;
END;
$$;

-- =====================================================================
-- Tasks
-- =====================================================================
CREATE VIEW v_task_detail AS
SELECT t.id, t.project_id, p.name AS project_name, t.assignee_id, u.full_name AS assignee_name,
       t.title, t.description, t.status, t.priority, t.progress, t.due_date,
       -- overdue uses the database clock, same as the reports
       COALESCE(t.status <> 'done' AND t.due_date < current_date, false) AS is_overdue,
       t.completed_at, t.created_at, t.updated_at
FROM tasks t
JOIN projects p   ON p.id = t.project_id
LEFT JOIN users u ON u.id = t.assignee_id;

CREATE OR REPLACE FUNCTION fn_task_list(
    p_project_id  integer DEFAULT NULL,
    p_assignee_id integer DEFAULT NULL,
    p_status      varchar DEFAULT NULL,
    p_priority    varchar DEFAULT NULL,
    p_overdue     boolean DEFAULT NULL,   -- true = only open tasks past their due date
    p_limit       integer DEFAULT 20,
    p_offset      integer DEFAULT 0)
RETURNS TABLE (total_count integer, item v_task_detail)
LANGUAGE sql STABLE AS $$
    WITH filtered AS (
        SELECT v AS item
        FROM v_task_detail v
        WHERE (p_project_id  IS NULL OR v.project_id  = p_project_id)
          AND (p_assignee_id IS NULL OR v.assignee_id = p_assignee_id)
          AND (p_status      IS NULL OR v.status      = p_status)
          AND (p_priority    IS NULL OR v.priority    = p_priority)
          AND (p_overdue     IS NOT TRUE OR v.is_overdue)
    ), page AS (
        SELECT item, row_number() OVER (ORDER BY (item).due_date NULLS LAST, (item).id) AS rn
        FROM filtered
        ORDER BY rn
        LIMIT p_limit OFFSET p_offset
    )
    SELECT (SELECT count(*) FROM filtered)::int, page.item
    FROM (SELECT 1) one
    LEFT JOIN page ON true
    ORDER BY page.rn;
$$;

CREATE OR REPLACE FUNCTION fn_task_get(p_id integer) RETURNS SETOF v_task_detail
LANGUAGE sql STABLE AS $$
    SELECT * FROM v_task_detail WHERE id = p_id;
$$;

-- progress / completed_at may be adjusted by trg_tasks_sync_completion
CREATE OR REPLACE PROCEDURE sp_task_create(
    p_project_id  integer,
    p_assignee_id integer,
    p_title       varchar,
    p_description text,
    p_status      varchar,
    p_priority    varchar,
    p_progress    smallint,
    p_due_date    date,
    INOUT p_id    integer DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO tasks (project_id, assignee_id, title, description, status, priority, progress, due_date)
    VALUES (p_project_id, p_assignee_id, p_title, p_description, p_status, p_priority, p_progress, p_due_date)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_task_update(
    p_id          integer,
    p_project_id  integer,
    p_assignee_id integer,
    p_title       varchar,
    p_description text,
    p_status      varchar,
    p_priority    varchar,
    p_progress    smallint,
    p_due_date    date,
    INOUT p_found boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE tasks
    SET project_id = p_project_id, assignee_id = p_assignee_id, title = p_title,
        description = p_description, status = p_status, priority = p_priority,
        progress = p_progress, due_date = p_due_date
    WHERE id = p_id;
    p_found := FOUND;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_task_delete(p_id integer, INOUT p_found boolean DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM tasks WHERE id = p_id;
    p_found := FOUND;
END;
$$;

-- =====================================================================
-- System logs (read-only; rows are written by audit_row_change trigger)
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_system_log_list(
    p_source    varchar     DEFAULT NULL,
    p_action    varchar     DEFAULT NULL,
    p_level     varchar     DEFAULT NULL,
    p_entity_id integer     DEFAULT NULL,
    p_from      timestamptz DEFAULT NULL,
    p_to        timestamptz DEFAULT NULL,
    p_limit     integer     DEFAULT 20,
    p_offset    integer     DEFAULT 0)
RETURNS TABLE (total_count integer, item system_logs)
LANGUAGE sql STABLE AS $$
    WITH filtered AS (
        SELECT l AS item
        FROM system_logs l
        WHERE (p_source    IS NULL OR l.source    = p_source)
          AND (p_action    IS NULL OR l.action    = p_action)
          AND (p_level     IS NULL OR l.level     = p_level)
          AND (p_entity_id IS NULL OR l.entity_id = p_entity_id)
          AND (p_from      IS NULL OR l.created_at >= p_from)
          AND (p_to        IS NULL OR l.created_at <  p_to)
    ), page AS (
        SELECT item, row_number() OVER (ORDER BY (item).id DESC) AS rn
        FROM filtered
        ORDER BY rn
        LIMIT p_limit OFFSET p_offset
    )
    SELECT (SELECT count(*) FROM filtered)::int, page.item
    FROM (SELECT 1) one
    LEFT JOIN page ON true
    ORDER BY page.rn;
$$;

-- ---------------------------------------------------------------------
-- Reports
-- LANGUAGE sql + STABLE lets the planner inline them like a view,
-- but unlike a view they take parameters.
-- ---------------------------------------------------------------------

-- Progress per department (department = owning department of the project).
-- Cancelled projects are excluded. p_department_id NULL = all departments.
CREATE OR REPLACE FUNCTION fn_report_department_progress(p_department_id integer DEFAULT NULL)
RETURNS TABLE (
    department_id      integer,
    department_name    varchar,
    total_projects     integer,
    active_projects    integer,
    completed_projects integer,
    total_tasks        integer,
    done_tasks         integer,
    in_progress_tasks  integer,
    overdue_tasks      integer,
    completion_rate    numeric(5,2),
    avg_progress       numeric(5,2),
    progress_rank      integer
)
LANGUAGE sql STABLE AS $$
    WITH task_stats AS (
        SELECT p.department_id,
               count(t.id)                                                      AS total_tasks,
               count(t.id) FILTER (WHERE t.status = 'done')                     AS done_tasks,
               count(t.id) FILTER (WHERE t.status IN ('in_progress', 'review')) AS in_progress_tasks,
               count(t.id) FILTER (WHERE t.status <> 'done'
                                     AND t.due_date < current_date)             AS overdue_tasks,
               avg(t.progress)                                                  AS avg_progress
        FROM projects p
        LEFT JOIN tasks t ON t.project_id = p.id
        WHERE p.status <> 'cancelled'
        GROUP BY p.department_id
    ), project_stats AS (
        SELECT department_id,
               count(*)                                    AS total_projects,
               count(*) FILTER (WHERE status = 'active')    AS active_projects,
               count(*) FILTER (WHERE status = 'completed') AS completed_projects
        FROM projects
        WHERE status <> 'cancelled'
        GROUP BY department_id
    ), ranked AS (
        SELECT d.id                                    AS department_id,
               d.name                                  AS department_name,
               COALESCE(ps.total_projects, 0)::int     AS total_projects,
               COALESCE(ps.active_projects, 0)::int    AS active_projects,
               COALESCE(ps.completed_projects, 0)::int AS completed_projects,
               COALESCE(ts.total_tasks, 0)::int        AS total_tasks,
               COALESCE(ts.done_tasks, 0)::int         AS done_tasks,
               COALESCE(ts.in_progress_tasks, 0)::int  AS in_progress_tasks,
               COALESCE(ts.overdue_tasks, 0)::int      AS overdue_tasks,
               -- % of tasks finished
               COALESCE(round(100.0 * ts.done_tasks / NULLIF(ts.total_tasks, 0), 2), 0)::numeric(5,2) AS completion_rate,
               -- average of per-task progress (0-100)
               COALESCE(round(ts.avg_progress, 2), 0)::numeric(5,2)                                    AS avg_progress,
               -- rank is computed over ALL departments, before the optional filter below
               dense_rank() OVER (ORDER BY COALESCE(ts.avg_progress, 0) DESC)::int                      AS progress_rank
        FROM departments d
        LEFT JOIN project_stats ps ON ps.department_id = d.id
        LEFT JOIN task_stats    ts ON ts.department_id = d.id
    )
    SELECT *
    FROM ranked r
    WHERE p_department_id IS NULL OR r.department_id = p_department_id
    ORDER BY r.progress_rank, r.department_name;
$$;

-- Progress per project, late projects first.
CREATE OR REPLACE FUNCTION fn_report_project_progress(
    p_department_id integer DEFAULT NULL,
    p_status        varchar DEFAULT NULL)
RETURNS TABLE (
    project_id      integer,
    project_name    varchar,
    department_name varchar,
    owner_name      varchar,
    status          varchar,
    end_date        date,
    total_tasks     integer,
    done_tasks      integer,
    overdue_tasks   integer,
    avg_progress    numeric(5,2),
    is_late         boolean
)
LANGUAGE sql STABLE AS $$
    SELECT p.id,
           p.name,
           d.name,
           u.full_name,
           p.status,
           p.end_date,
           count(t.id)::int,
           count(t.id) FILTER (WHERE t.status = 'done')::int,
           count(t.id) FILTER (WHERE t.status <> 'done' AND t.due_date < current_date)::int,
           COALESCE(round(avg(t.progress), 2), 0)::numeric(5,2),
           (p.end_date IS NOT NULL AND p.end_date < current_date
                AND p.status NOT IN ('completed', 'cancelled'))
    FROM projects p
    JOIN departments d ON d.id = p.department_id
    LEFT JOIN users  u ON u.id = p.owner_id
    LEFT JOIN tasks  t ON t.project_id = p.id
    WHERE (p_department_id IS NULL OR p.department_id = p_department_id)
      AND (p_status IS NULL OR p.status = p_status)
    GROUP BY p.id, d.name, u.full_name
    ORDER BY 11 DESC, 10, 2;   -- is_late DESC, avg_progress, project_name
$$;

-- Open / overdue / recently finished tasks per active user.
CREATE OR REPLACE FUNCTION fn_report_user_workload(p_department_id integer DEFAULT NULL)
RETURNS TABLE (
    user_id             integer,
    full_name           varchar,
    department_name     varchar,
    open_tasks          integer,
    critical_open_tasks integer,
    overdue_tasks       integer,
    done_last_month     integer
)
LANGUAGE sql STABLE AS $$
    SELECT u.id,
           u.full_name,
           d.name,
           count(t.id) FILTER (WHERE t.status <> 'done')::int,
           count(t.id) FILTER (WHERE t.status <> 'done' AND t.priority = 'critical')::int,
           count(t.id) FILTER (WHERE t.status <> 'done' AND t.due_date < current_date)::int,
           count(t.id) FILTER (WHERE t.completed_at >= now() - interval '30 days')::int
    FROM users u
    JOIN departments d ON d.id = u.department_id
    LEFT JOIN tasks t  ON t.assignee_id = u.id
    WHERE u.is_active
      AND (p_department_id IS NULL OR u.department_id = p_department_id)
    GROUP BY u.id, u.full_name, d.name
    ORDER BY 4 DESC, 2;        -- open_tasks DESC, full_name
$$;

COMMIT;
