-- Analytics Metrics Function
-- Returns comprehensive analytics metrics for performance monitoring
-- Input: since_timestamp for time-based filtering
-- Output: Single row with all analytics metrics

CREATE OR REPLACE FUNCTION get_analytics_metrics_v01(since_timestamp TIMESTAMPTZ DEFAULT NULL)
RETURNS TABLE (
    -- System overview metrics
    active_tasks_count BIGINT,
    total_namespaces_count BIGINT,
    unique_task_types_count BIGINT,
    system_health_score NUMERIC(5,3),
    
    -- Performance metrics since timestamp
    task_throughput BIGINT,
    completion_count BIGINT,
    error_count BIGINT,
    completion_rate NUMERIC(5,2),
    error_rate NUMERIC(5,2),
    
    -- Duration metrics (in seconds)
    avg_task_duration NUMERIC(10,3),
    avg_step_duration NUMERIC(10,3),
    step_throughput BIGINT,
    
    -- Metadata
    analysis_period_start TIMESTAMPTZ,
    calculated_at TIMESTAMPTZ
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    analysis_start TIMESTAMPTZ;
BEGIN
    -- Set analysis start time (default to 1 hour ago if not provided)
    analysis_start := COALESCE(since_timestamp, NOW() - INTERVAL '1 hour');
    
    RETURN QUERY
    WITH active_tasks AS (
        SELECT COUNT(DISTINCT t.task_id) as active_count
        FROM tasker_tasks t
        INNER JOIN tasker_workflow_steps ws ON ws.task_id = t.task_id
        INNER JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = ws.workflow_step_id
        WHERE wst.most_recent = true
          AND wst.to_state NOT IN ('complete', 'error', 'skipped', 'resolved_manually')
    ),
    namespace_summary AS (
        SELECT COUNT(DISTINCT tn.name) as namespace_count
        FROM tasker_task_namespaces tn
        INNER JOIN tasker_named_tasks nt ON nt.task_namespace_id = tn.task_namespace_id
        INNER JOIN tasker_tasks t ON t.named_task_id = nt.named_task_id
    ),
    task_type_summary AS (
        SELECT COUNT(DISTINCT nt.name) as task_type_count
        FROM tasker_named_tasks nt
        INNER JOIN tasker_tasks t ON t.named_task_id = nt.named_task_id
    ),
    recent_task_health AS (
        SELECT 
            COUNT(DISTINCT t.task_id) as total_recent_tasks,
            COUNT(DISTINCT t.task_id) FILTER (
                WHERE wst.to_state = 'complete' AND wst.most_recent = true
            ) as completed_tasks,
            COUNT(DISTINCT t.task_id) FILTER (
                WHERE wst.to_state = 'error' AND wst.most_recent = true
            ) as error_tasks
        FROM tasker_tasks t
        INNER JOIN tasker_workflow_steps ws ON ws.task_id = t.task_id
        INNER JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = ws.workflow_step_id
        WHERE t.created_at > NOW() - INTERVAL '1 hour'
    ),
    period_metrics AS (
        SELECT 
            COUNT(DISTINCT t.task_id) as throughput,
            COUNT(DISTINCT t.task_id) FILTER (
                WHERE completed_wst.to_state = 'complete' AND completed_wst.most_recent = true
            ) as completions,
            COUNT(DISTINCT t.task_id) FILTER (
                WHERE error_wst.to_state = 'error' AND error_wst.most_recent = true
            ) as errors,
            COUNT(DISTINCT ws.workflow_step_id) as step_count,
            AVG(
                CASE 
                    WHEN completed_wst.to_state = 'complete' AND completed_wst.most_recent = true
                    THEN EXTRACT(EPOCH FROM (completed_wst.created_at - t.created_at))
                    ELSE NULL
                END
            ) as avg_task_seconds,
            AVG(
                CASE 
                    WHEN step_completed.to_state = 'complete' AND step_completed.most_recent = true
                    THEN EXTRACT(EPOCH FROM (step_completed.created_at - ws.created_at))
                    ELSE NULL
                END
            ) as avg_step_seconds
        FROM tasker_tasks t
        LEFT JOIN tasker_workflow_steps ws ON ws.task_id = t.task_id
        LEFT JOIN tasker_workflow_step_transitions completed_wst ON completed_wst.workflow_step_id = ws.workflow_step_id
            AND completed_wst.to_state = 'complete' AND completed_wst.most_recent = true
        LEFT JOIN tasker_workflow_step_transitions error_wst ON error_wst.workflow_step_id = ws.workflow_step_id
            AND error_wst.to_state = 'error' AND error_wst.most_recent = true
        LEFT JOIN tasker_workflow_step_transitions step_completed ON step_completed.workflow_step_id = ws.workflow_step_id
            AND step_completed.to_state = 'complete' AND step_completed.most_recent = true
        WHERE t.created_at > analysis_start
    )
    SELECT 
        at.active_count,
        ns.namespace_count,
        tts.task_type_count,
        CASE 
            WHEN (rth.completed_tasks + rth.error_tasks) > 0 
            THEN ROUND((rth.completed_tasks::NUMERIC / (rth.completed_tasks + rth.error_tasks)), 3)
            ELSE 1.0
        END as health_score,
        pm.throughput,
        pm.completions,
        pm.errors,
        CASE 
            WHEN pm.throughput > 0 
            THEN ROUND((pm.completions::NUMERIC / pm.throughput * 100), 2)
            ELSE 0.0
        END as completion_rate_pct,
        CASE 
            WHEN pm.throughput > 0 
            THEN ROUND((pm.errors::NUMERIC / pm.throughput * 100), 2)
            ELSE 0.0
        END as error_rate_pct,
        ROUND(COALESCE(pm.avg_task_seconds, 0), 3),
        ROUND(COALESCE(pm.avg_step_seconds, 0), 3),
        pm.step_count,
        analysis_start,
        NOW()
    FROM active_tasks at
    CROSS JOIN namespace_summary ns
    CROSS JOIN task_type_summary tts
    CROSS JOIN recent_task_health rth
    CROSS JOIN period_metrics pm;
END;
$$;