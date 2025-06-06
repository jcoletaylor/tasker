SELECT
  t.task_id,

  -- Include all existing TaskExecutionContext fields
  tec.total_steps,
  tec.pending_steps,
  tec.in_progress_steps,
  tec.completed_steps,
  tec.failed_steps,
  tec.ready_steps,
  tec.execution_status,
  tec.recommended_action,
  tec.completion_percentage,
  tec.health_status,

  -- Enhanced processing context
  root_steps.root_step_ids,
  root_steps.root_step_count,

  -- Blocking analysis with specific step identification
  blocking_info.blocked_step_ids,
  blocking_info.blocking_reasons,

  -- Next processing recommendation with actionable step IDs
  CASE
    WHEN tec.ready_steps > 0 THEN ready_steps.ready_step_ids
    ELSE NULL
  END as next_executable_step_ids,

  -- Processing strategy recommendation based on ready step count
  CASE
    WHEN tec.ready_steps > 5 THEN 'batch_parallel'
    WHEN tec.ready_steps > 1 THEN 'small_parallel'
    WHEN tec.ready_steps = 1 THEN 'sequential'
    ELSE 'waiting'
  END as processing_strategy

FROM tasker_tasks t
JOIN tasker_task_execution_contexts tec ON tec.task_id = t.task_id

LEFT JOIN (
  SELECT
    task_id,
    jsonb_agg(workflow_step_id ORDER BY workflow_step_id) as root_step_ids,
    count(*) as root_step_count
  FROM tasker_step_readiness_statuses srs
  WHERE srs.total_parents = 0
  GROUP BY task_id
) root_steps ON root_steps.task_id = t.task_id

LEFT JOIN (
  SELECT
    task_id,
    jsonb_agg(workflow_step_id ORDER BY workflow_step_id) as ready_step_ids
  FROM tasker_step_readiness_statuses srs
  WHERE srs.ready_for_execution = true
  GROUP BY task_id
) ready_steps ON ready_steps.task_id = t.task_id

LEFT JOIN (
  SELECT
    task_id,
    jsonb_agg(workflow_step_id ORDER BY workflow_step_id) as blocked_step_ids,
    jsonb_agg(
      CASE
        WHEN srs.dependencies_satisfied = false THEN 'dependencies_not_satisfied'
        WHEN srs.retry_eligible = false THEN 'retry_not_eligible'
        WHEN srs.current_state NOT IN ('pending', 'failed') THEN 'invalid_state'
        ELSE 'unknown'
      END ORDER BY workflow_step_id
    ) as blocking_reasons
  FROM tasker_step_readiness_statuses srs
  WHERE srs.ready_for_execution = false
    AND srs.current_state IN ('pending', 'failed')
  GROUP BY task_id
) blocking_info ON blocking_info.task_id = t.task_id
