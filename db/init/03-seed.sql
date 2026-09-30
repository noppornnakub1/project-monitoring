-- Sample data so the API and reports return something useful right away.
BEGIN;

INSERT INTO departments (name) VALUES
    ('Engineering'), ('Marketing'), ('Finance'), ('Operations');

INSERT INTO users (department_id, full_name, email, role) VALUES
    (1, 'Somchai Jaidee',    'somchai@example.com',  'manager'),
    (1, 'Suda Rakdee',       'suda@example.com',     'member'),
    (1, 'Anan Srisuk',       'anan@example.com',     'member'),
    (2, 'Malee Wongsa',      'malee@example.com',    'manager'),
    (2, 'Preecha Boonmee',   'preecha@example.com',  'member'),
    (3, 'Kanya Thongdee',    'kanya@example.com',    'manager'),
    (4, 'Wichai Saetang',    'wichai@example.com',   'admin');

INSERT INTO projects (department_id, owner_id, name, description, status, start_date, end_date) VALUES
    (1, 1, 'Customer Portal v2',      'Rewrite of the customer self-service portal', 'active',    current_date - 60, current_date + 30),
    (1, 1, 'CI/CD Migration',         'Move pipelines to containers',                'active',    current_date - 20, current_date - 1),
    (2, 4, 'Q4 Campaign',             'End-of-year marketing campaign',              'planning',  current_date,      current_date + 90),
    (3, 6, 'Budget Automation',       'Automate monthly budget reports',             'completed', current_date - 120, current_date - 10),
    (4, 7, 'Warehouse Relocation',    NULL,                                          'on_hold',   current_date - 5,  NULL);

INSERT INTO tasks (project_id, assignee_id, title, status, priority, progress, due_date) VALUES
    (1, 2, 'Design login flow',          'done',        'high',     100, current_date - 30),
    (1, 3, 'Implement profile API',      'in_progress', 'high',      60, current_date + 5),
    (1, 2, 'Payment page',               'todo',        'critical',   0, current_date - 2),
    (1, 3, 'E2E tests',                  'todo',        'medium',     0, current_date + 25),
    (2, 3, 'Dockerize services',         'review',      'high',      90, current_date - 3),
    (2, 1, 'Setup registry',             'done',        'medium',   100, current_date - 10),
    (3, 5, 'Define target audience',     'in_progress', 'medium',    40, current_date + 10),
    (3, 4, 'Book media slots',           'todo',        'low',        0, current_date + 45),
    (4, 6, 'Collect requirements',       'done',        'medium',   100, current_date - 100),
    (4, 6, 'Build report generator',     'done',        'high',     100, current_date - 20),
    (5, 7, 'Survey new site',            'in_progress', 'medium',    30, current_date + 15);

COMMIT;
