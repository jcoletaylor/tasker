SELECT
  t.task_id,
  t.named_task_id,
  COALESCE(task_state.to_state, 'pending') as status,

  -- Step Statistics (using optimized aggregation)
  step_stats.total_steps,
  step_stats.pending_steps,
  step_stats.in_progress_steps,
  step_stats.completed_steps,
  step_stats.failed_steps,
  step_stats.ready_steps,

  -- Execution State
  CASE
    WHEN step_stats.ready_steps > 0 THEN 'has_ready_steps'
    WHEN step_stats.in_progress_steps > 0 THEN 'processing'
    WHEN step_stats.failed_steps > 0 AND step_stats.ready_steps = 0 THEN 'blocked_by_failures'
    WHEN step_stats.completed_steps = step_stats.total_steps THEN 'all_complete'
    ELSE 'waiting_for_dependencies'
  END as execution_status,

  -- Next Action Recommendations
  CASE
    WHEN step_stats.ready_steps > 0 THEN 'execute_ready_steps'
    WHEN step_stats.in_progress_steps > 0 THEN 'wait_for_completion'
    WHEN step_stats.failed_steps > 0 AND step_stats.ready_steps = 0 THEN 'handle_failures'
    WHEN step_stats.completed_steps = step_stats.total_steps THEN 'finalize_task'
    ELSE 'wait_for_dependencies'
  END as recommended_action,

  -- Progress Metrics
  CASE
    WHEN step_stats.total_steps = 0 THEN 0.0
    ELSE ROUND((step_stats.completed_steps::decimal / step_stats.total_steps::decimal) * 100, 2)
  END as completion_percentage,

  -- Health Indicators
  CASE
    WHEN step_stats.failed_steps = 0 THEN 'healthy'
    WHEN step_stats.failed_steps > 0 AND step_stats.ready_steps > 0 THEN 'recovering'
    WHEN step_stats.failed_steps > 0 AND step_stats.ready_steps = 0 THEN 'blocked'
    ELSE 'unknown'
  END as health_status

FROM tasker_tasks t

-- OPTIMIZED: Current Task State using most_recent flag
LEFT JOIN tasker_task_transitions task_state
  ON task_state.task_id = t.task_id
  AND task_state.most_recent = true

-- OPTIMIZED: Step statistics using single query with better indexes
JOIN (
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
) step_stats ON step_stats.task_id = t.task_id
