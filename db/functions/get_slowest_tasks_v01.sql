-- Slowest Tasks Analysis Function
-- Returns the slowest tasks within a specified time period with performance metrics
-- Input: since_timestamp, limit_count, and optional namespace/name/version filters
-- Output: Ranked list of slowest tasks with duration and context

CREATE OR REPLACE FUNCTION get_slowest_tasks_v01(
    since_timestamp TIMESTAMPTZ DEFAULT NULL,
    limit_count INTEGER DEFAULT 10,
    namespace_filter TEXT DEFAULT NULL,
    task_name_filter TEXT DEFAULT NULL,
    version_filter TEXT DEFAULT NULL
)
RETURNS TABLE (
    task_id BIGINT,
    task_name VARCHAR(64),
    namespace_name VARCHAR(64), 
    version VARCHAR(64),
    duration_seconds NUMERIC(10,3),
    step_count BIGINT,
    completed_steps BIGINT,
    error_steps BIGINT,
    created_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    initiator VARCHAR(128),
    source_system VARCHAR(128)
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    analysis_start TIMESTAMPTZ;
BEGIN
    -- Set analysis start time (default to 24 hours ago if not provided)
    analysis_start := COALESCE(since_timestamp, NOW() - INTERVAL '24 hours');
    
    RETURN QUERY
    WITH task_durations AS (
        SELECT 
            t.task_id,
            nt.name as task_name,
            tn.name as namespace_name,
            nt.version,
            t.created_at,
            t.initiator,
            t.source_system,
            -- Find the latest completion time across all steps
            MAX(wst.created_at) FILTER (
                WHERE wst.to_state IN ('complete', 'error') AND wst.most_recent = true
            ) as latest_completion,
            -- Calculate duration from task creation to latest step completion
            EXTRACT(EPOCH FROM (
                MAX(wst.created_at) FILTER (
                    WHERE wst.to_state IN ('complete', 'error') AND wst.most_recent = true
                ) - t.created_at
            )) as duration_seconds,
            COUNT(ws.workflow_step_id) as total_steps,
            COUNT(ws.workflow_step_id) FILTER (
                WHERE complete_wst.to_state = 'complete' AND complete_wst.most_recent = true
            ) as completed_step_count,
            COUNT(ws.workflow_step_id) FILTER (
                WHERE error_wst.to_state = 'error' AND error_wst.most_recent = true
            ) as error_step_count
        FROM tasker_tasks t
        INNER JOIN tasker_named_tasks nt ON nt.named_task_id = t.named_task_id
        INNER JOIN tasker_task_namespaces tn ON tn.task_namespace_id = nt.task_namespace_id
        INNER JOIN tasker_workflow_steps ws ON ws.task_id = t.task_id
        LEFT JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = ws.workflow_step_id
        LEFT JOIN tasker_workflow_step_transitions complete_wst ON complete_wst.workflow_step_id = ws.workflow_step_id
            AND complete_wst.to_state = 'complete' AND complete_wst.most_recent = true
        LEFT JOIN tasker_workflow_step_transitions error_wst ON error_wst.workflow_step_id = ws.workflow_step_id
            AND error_wst.to_state = 'error' AND error_wst.most_recent = true
        WHERE t.created_at > analysis_start
          AND (namespace_filter IS NULL OR tn.name = namespace_filter)
          AND (task_name_filter IS NULL OR nt.name = task_name_filter)
          AND (version_filter IS NULL OR nt.version = version_filter)
        GROUP BY t.task_id, nt.name, tn.name, nt.version, t.created_at, t.initiator, t.source_system
        HAVING MAX(wst.created_at) FILTER (
            WHERE wst.to_state IN ('complete', 'error') AND wst.most_recent = true
        ) IS NOT NULL  -- Only include tasks that have at least one completed/failed step
    )
    SELECT 
        td.task_id,
        td.task_name,
        td.namespace_name,
        td.version,
        ROUND(td.duration_seconds, 3),
        td.total_steps,
        td.completed_step_count,
        td.error_step_count,
        td.created_at,
        td.latest_completion,
        td.initiator,
        td.source_system
    FROM task_durations td
    WHERE td.duration_seconds IS NOT NULL
    ORDER BY td.duration_seconds DESC
    LIMIT limit_count;
END;
$$;