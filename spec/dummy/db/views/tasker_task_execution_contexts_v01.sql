-- OPTIMIZED Task Execution Context View
-- This version uses the `complete` boolean to provide different views for completed vs active tasks
-- Significant performance improvement by handling completed tasks separately

-- Optimized Task Execution Context View
-- This version eliminates the expensive subquery by using a CTE approach
-- that avoids the window function + GROUP BY conflict

WITH step_aggregates AS (
  SELECT
    ws.task_id,
    COUNT(*) as total_steps,
    COUNT(CASE WHEN srs.current_state = 'pending' THEN 1 END) as pending_steps,
    COUNT(CASE WHEN srs.current_state = 'in_progress' THEN 1 END) as in_progress_steps,
    COUNT(CASE WHEN srs.current_state = 'complete' THEN 1 END) as completed_steps,
    COUNT(CASE WHEN srs.current_state = 'error' THEN 1 END) as failed_steps,
    COUNT(CASE WHEN srs.ready_for_execution = true THEN 1 END) as ready_steps
  FROM tasker_workflow_steps ws
  JOIN tasker_step_readiness_statuses srs ON srs.workflow_step_id = ws.workflow_step_id
  GROUP BY ws.task_id
)

SELECT
  t.task_id,
  t.named_task_id,
  COALESCE(task_state.to_state, 'pending') as status,

  -- Step Statistics (from CTE, with defaults for tasks without step readiness entries)
  COALESCE(step_aggregates.total_steps, 0) as total_steps,
  COALESCE(step_aggregates.pending_steps, 0) as pending_steps,
  COALESCE(step_aggregates.in_progress_steps, 0) as in_progress_steps,
  COALESCE(step_aggregates.completed_steps, 0) as completed_steps,
  COALESCE(step_aggregates.failed_steps, 0) as failed_steps,
  COALESCE(step_aggregates.ready_steps, 0) as ready_steps,

  -- Execution State
  CASE
    WHEN COALESCE(step_aggregates.ready_steps, 0) > 0 THEN 'has_ready_steps'
    WHEN COALESCE(step_aggregates.in_progress_steps, 0) > 0 THEN 'processing'
    WHEN COALESCE(step_aggregates.failed_steps, 0) > 0 AND COALESCE(step_aggregates.ready_steps, 0) = 0 THEN 'blocked_by_failures'
    WHEN COALESCE(step_aggregates.completed_steps, 0) = COALESCE(step_aggregates.total_steps, 0) AND COALESCE(step_aggregates.total_steps, 0) > 0 THEN 'all_complete'
    ELSE 'waiting_for_dependencies'
  END as execution_status,

  -- Next Action Recommendations
  CASE
    WHEN COALESCE(step_aggregates.ready_steps, 0) > 0 THEN 'execute_ready_steps'
    WHEN COALESCE(step_aggregates.in_progress_steps, 0) > 0 THEN 'wait_for_completion'
    WHEN COALESCE(step_aggregates.failed_steps, 0) > 0 AND COALESCE(step_aggregates.ready_steps, 0) = 0 THEN 'handle_failures'
    WHEN COALESCE(step_aggregates.completed_steps, 0) = COALESCE(step_aggregates.total_steps, 0) AND COALESCE(step_aggregates.total_steps, 0) > 0 THEN 'finalize_task'
    ELSE 'wait_for_dependencies'
  END as recommended_action,

  -- Progress Metrics
  CASE
    WHEN COALESCE(step_aggregates.total_steps, 0) = 0 THEN 0.0
    ELSE ROUND((COALESCE(step_aggregates.completed_steps, 0)::decimal / COALESCE(step_aggregates.total_steps, 1)::decimal) * 100, 2)
  END as completion_percentage,

  -- Health Indicators
  CASE
    WHEN COALESCE(step_aggregates.failed_steps, 0) = 0 THEN 'healthy'
    WHEN COALESCE(step_aggregates.failed_steps, 0) > 0 AND COALESCE(step_aggregates.ready_steps, 0) > 0 THEN 'recovering'
    WHEN COALESCE(step_aggregates.failed_steps, 0) > 0 AND COALESCE(step_aggregates.ready_steps, 0) = 0 THEN 'blocked'
    ELSE 'unknown'
  END as health_status

FROM tasker_tasks t

-- OPTIMIZED: Current Task State using most_recent flag
LEFT JOIN tasker_task_transitions task_state
  ON task_state.task_id = t.task_id
  AND task_state.most_recent = true

-- OPTIMIZED: Left join with pre-aggregated step statistics to handle tasks without steps
LEFT JOIN step_aggregates ON step_aggregates.task_id = t.task_id
