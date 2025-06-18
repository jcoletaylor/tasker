-- System Health Counts Function
-- Returns comprehensive system health metrics in a single query
-- No input parameters needed - returns system-wide counts
-- Output: Single row with all health counts and metrics

CREATE OR REPLACE FUNCTION get_system_health_counts_v01()
RETURNS TABLE (
    -- Task counts
    total_tasks BIGINT,
    pending_tasks BIGINT,
    in_progress_tasks BIGINT,
    complete_tasks BIGINT,
    error_tasks BIGINT,
    cancelled_tasks BIGINT,

    -- Step counts
    total_steps BIGINT,
    pending_steps BIGINT,
    in_progress_steps BIGINT,
    complete_steps BIGINT,
    error_steps BIGINT,

    -- Retry-specific counts
    retryable_error_steps BIGINT,
    exhausted_retry_steps BIGINT,
    in_backoff_steps BIGINT,

    -- Database metrics
    active_connections BIGINT,
    max_connections BIGINT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH task_counts AS (
        SELECT
            COUNT(*) as total_tasks,
            COUNT(*) FILTER (WHERE task_state.to_state = 'pending') as pending_tasks,
            COUNT(*) FILTER (WHERE task_state.to_state = 'in_progress') as in_progress_tasks,
            COUNT(*) FILTER (WHERE task_state.to_state = 'complete') as complete_tasks,
            COUNT(*) FILTER (WHERE task_state.to_state = 'error') as error_tasks,
            COUNT(*) FILTER (WHERE task_state.to_state = 'cancelled') as cancelled_tasks
        FROM tasker_tasks t
        LEFT JOIN tasker_task_transitions task_state ON task_state.task_id = t.task_id
            AND task_state.most_recent = true
    ),
    step_counts AS (
        SELECT
            COUNT(*) as total_steps,
            COUNT(*) FILTER (WHERE step_state.to_state = 'pending') as pending_steps,
            COUNT(*) FILTER (WHERE step_state.to_state = 'in_progress') as in_progress_steps,
            COUNT(*) FILTER (WHERE step_state.to_state = 'complete') as complete_steps,
            COUNT(*) FILTER (WHERE step_state.to_state = 'error') as error_steps,

            -- Retry-specific logic - retryable errors
            COUNT(*) FILTER (
                WHERE step_state.to_state = 'error'
                AND ws.attempts < ws.retry_limit
                AND COALESCE(ws.retryable, true) = true
            ) as retryable_error_steps,

            -- Exhausted retries
            COUNT(*) FILTER (
                WHERE step_state.to_state = 'error'
                AND ws.attempts >= ws.retry_limit
            ) as exhausted_retry_steps,

            -- In backoff (error state but not exhausted retries and has last_attempted_at)
            COUNT(*) FILTER (
                WHERE step_state.to_state = 'error'
                AND ws.attempts < ws.retry_limit
                AND COALESCE(ws.retryable, true) = true
                AND ws.last_attempted_at IS NOT NULL
            ) as in_backoff_steps

        FROM tasker_workflow_steps ws
        LEFT JOIN tasker_workflow_step_transitions step_state ON step_state.workflow_step_id = ws.workflow_step_id
            AND step_state.most_recent = true
    ),
    connection_info AS (
        SELECT
            COUNT(*) as active_connections,
            COALESCE((SELECT setting::BIGINT FROM pg_settings WHERE name = 'max_connections'), 0) as max_connections
        FROM pg_stat_activity
        WHERE datname = current_database()
            AND state = 'active'
    )
    SELECT
        tc.total_tasks,
        tc.pending_tasks,
        tc.in_progress_tasks,
        tc.complete_tasks,
        tc.error_tasks,
        tc.cancelled_tasks,
        sc.total_steps,
        sc.pending_steps,
        sc.in_progress_steps,
        sc.complete_steps,
        sc.error_steps,
        sc.retryable_error_steps,
        sc.exhausted_retry_steps,
        sc.in_backoff_steps,
        ci.active_connections,
        ci.max_connections
    FROM task_counts tc
    CROSS JOIN step_counts sc
    CROSS JOIN connection_info ci;
END;
$$;
