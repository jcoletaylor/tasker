-- Slowest Steps Analysis Function  
-- Returns the slowest workflow steps within a specified time period
-- Input: since_timestamp, limit_count, and optional filters
-- Output: Ranked list of slowest steps with duration and context

CREATE OR REPLACE FUNCTION get_slowest_steps_v01(
    since_timestamp TIMESTAMPTZ DEFAULT NULL,
    limit_count INTEGER DEFAULT 10,
    namespace_filter TEXT DEFAULT NULL,
    task_name_filter TEXT DEFAULT NULL,
    version_filter TEXT DEFAULT NULL
)
RETURNS TABLE (
    workflow_step_id BIGINT,
    task_id BIGINT,
    step_name VARCHAR(128),
    task_name VARCHAR(64),
    namespace_name VARCHAR(64),
    version VARCHAR(64),
    duration_seconds NUMERIC(10,3),
    attempts INTEGER,
    created_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retryable BOOLEAN,
    step_status VARCHAR(64)
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    analysis_start TIMESTAMPTZ;
BEGIN
    -- Set analysis start time (default to 24 hours ago if not provided)
    analysis_start := COALESCE(since_timestamp, NOW() - INTERVAL '24 hours');
    
    RETURN QUERY
    WITH step_durations AS (
        SELECT 
            ws.workflow_step_id,
            ws.task_id,
            ns.name as step_name,
            nt.name as task_name,
            tn.name as namespace_name,
            nt.version,
            ws.created_at,
            ws.attempts,
            ws.retryable,
            -- Find the completion time
            wst.created_at as completion_time,
            wst.to_state as final_state,
            -- Calculate duration from step creation to completion
            EXTRACT(EPOCH FROM (wst.created_at - ws.created_at)) as duration_seconds
        FROM tasker_workflow_steps ws
        INNER JOIN tasker_named_steps ns ON ns.named_step_id = ws.named_step_id
        INNER JOIN tasker_tasks t ON t.task_id = ws.task_id
        INNER JOIN tasker_named_tasks nt ON nt.named_task_id = t.named_task_id
        INNER JOIN tasker_task_namespaces tn ON tn.task_namespace_id = nt.task_namespace_id
        INNER JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = ws.workflow_step_id
        WHERE ws.created_at > analysis_start
          AND wst.most_recent = true
          AND wst.to_state = 'complete'  -- Only include completed steps for accurate duration
          AND (namespace_filter IS NULL OR tn.name = namespace_filter)
          AND (task_name_filter IS NULL OR nt.name = task_name_filter)
          AND (version_filter IS NULL OR nt.version = version_filter)
    )
    SELECT 
        sd.workflow_step_id,
        sd.task_id,
        sd.step_name,
        sd.task_name,
        sd.namespace_name,
        sd.version,
        ROUND(sd.duration_seconds, 3),
        sd.attempts,
        sd.created_at,
        sd.completion_time,
        sd.retryable,
        sd.final_state
    FROM step_durations sd
    WHERE sd.duration_seconds IS NOT NULL
      AND sd.duration_seconds > 0  -- Filter out negative durations (data integrity check)
    ORDER BY sd.duration_seconds DESC
    LIMIT limit_count;
END;
$$;