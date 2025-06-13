-- Batch Task Execution Context Function
-- Gets execution context for multiple tasks in a single query
-- Input: Array of task_ids
-- Output: Multiple rows with task execution context data

CREATE OR REPLACE FUNCTION get_task_execution_contexts_batch(input_task_ids BIGINT[])
RETURNS TABLE(
  task_id BIGINT,
  named_task_id INTEGER,
  status TEXT,
  total_steps BIGINT,
  pending_steps BIGINT,
  in_progress_steps BIGINT,
  completed_steps BIGINT,
  failed_steps BIGINT,
  ready_steps BIGINT,
  execution_status TEXT,
  recommended_action TEXT,
  completion_percentage DECIMAL,
  health_status TEXT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  WITH task_step_data AS (
    -- Get step readiness data for all tasks at once using batch function
    SELECT * FROM get_step_readiness_status_batch(input_task_ids)
  ),
  task_info AS (
    SELECT
      t.task_id,
      t.named_task_id,
      COALESCE(task_state.to_state, 'pending')::TEXT as current_status
    FROM unnest(input_task_ids) AS task_list(task_id)
    JOIN tasker_tasks t ON t.task_id = task_list.task_id
    LEFT JOIN tasker_task_transitions task_state
      ON task_state.task_id = t.task_id
      AND task_state.most_recent = true
  ),
  aggregated_stats AS (
    SELECT
      tsd.task_id,
      COUNT(*) as total_steps,
      COUNT(CASE WHEN tsd.current_state = 'pending' THEN 1 END) as pending_steps,
      COUNT(CASE WHEN tsd.current_state = 'in_progress' THEN 1 END) as in_progress_steps,
      COUNT(CASE WHEN tsd.current_state IN ('complete', 'resolved_manually') THEN 1 END) as completed_steps,
      COUNT(CASE WHEN tsd.current_state = 'error' THEN 1 END) as failed_steps,
      COUNT(CASE WHEN tsd.ready_for_execution = true THEN 1 END) as ready_steps
    FROM task_step_data tsd
    GROUP BY tsd.task_id
  )
  SELECT
    ti.task_id,
    ti.named_task_id,
    ti.current_status as status,

    -- Step Statistics
    COALESCE(ast.total_steps, 0) as total_steps,
    COALESCE(ast.pending_steps, 0) as pending_steps,
    COALESCE(ast.in_progress_steps, 0) as in_progress_steps,
    COALESCE(ast.completed_steps, 0) as completed_steps,
    COALESCE(ast.failed_steps, 0) as failed_steps,
    COALESCE(ast.ready_steps, 0) as ready_steps,

    -- Execution State Logic
    CASE
      WHEN COALESCE(ast.ready_steps, 0) > 0 THEN 'has_ready_steps'
      WHEN COALESCE(ast.in_progress_steps, 0) > 0 THEN 'processing'
      WHEN COALESCE(ast.failed_steps, 0) > 0 AND COALESCE(ast.ready_steps, 0) = 0 THEN 'blocked_by_failures'
      WHEN COALESCE(ast.completed_steps, 0) = COALESCE(ast.total_steps, 0) AND COALESCE(ast.total_steps, 0) > 0 THEN 'all_complete'
      ELSE 'waiting_for_dependencies'
    END as execution_status,

    -- Recommended Action Logic
    CASE
      WHEN COALESCE(ast.ready_steps, 0) > 0 THEN 'execute_ready_steps'
      WHEN COALESCE(ast.in_progress_steps, 0) > 0 THEN 'wait_for_completion'
      WHEN COALESCE(ast.failed_steps, 0) > 0 AND COALESCE(ast.ready_steps, 0) = 0 THEN 'handle_failures'
      WHEN COALESCE(ast.completed_steps, 0) = COALESCE(ast.total_steps, 0) AND COALESCE(ast.total_steps, 0) > 0 THEN 'finalize_task'
      ELSE 'wait_for_dependencies'
    END as recommended_action,

    -- Progress Metrics
    CASE
      WHEN COALESCE(ast.total_steps, 0) = 0 THEN 0.0
      ELSE ROUND((COALESCE(ast.completed_steps, 0)::decimal / COALESCE(ast.total_steps, 1)::decimal) * 100, 2)
    END as completion_percentage,

    -- Health Status Logic
    CASE
      WHEN COALESCE(ast.failed_steps, 0) = 0 THEN 'healthy'
      WHEN COALESCE(ast.failed_steps, 0) > 0 AND COALESCE(ast.ready_steps, 0) > 0 THEN 'recovering'
      WHEN COALESCE(ast.failed_steps, 0) > 0 AND COALESCE(ast.ready_steps, 0) = 0 THEN 'blocked'
      ELSE 'unknown'
    END as health_status

  FROM task_info ti
  LEFT JOIN aggregated_stats ast ON ast.task_id = ti.task_id;
END;
$$;
