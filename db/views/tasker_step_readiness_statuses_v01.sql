SELECT
  ws.workflow_step_id,
  ws.task_id,
  ws.named_step_id,
  ns.name,

  -- Current State Information
  COALESCE(current_state.to_state, 'pending') as current_state,

  -- Dependency Analysis
  CASE
    WHEN dep_check.total_parents = 0 THEN true
    WHEN dep_check.completed_parents = dep_check.total_parents THEN true
    ELSE false
  END as dependencies_satisfied,

  -- Retry & Backoff Analysis
  CASE
    WHEN ws.attempts >= COALESCE(ws.retry_limit, 3) THEN false
    WHEN last_failure.created_at IS NULL THEN true
    WHEN ws.backoff_request_seconds IS NOT NULL AND ws.last_attempted_at IS NOT NULL THEN
      -- Use explicit backoff_request_seconds if available
      CASE WHEN ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second') <= NOW()
           THEN true
           ELSE false
      END
    WHEN last_failure.created_at IS NOT NULL THEN
      -- Default exponential backoff: base_delay * (2^attempts), capped at 30 seconds
      CASE WHEN last_failure.created_at + (
        LEAST(power(2, COALESCE(ws.attempts, 1)) * interval '1 second', interval '30 seconds')
      ) <= NOW() THEN true ELSE false END
    ELSE true
  END as retry_eligible,

  -- Final Readiness Calculation
  CASE
    WHEN COALESCE(current_state.to_state, 'pending') IN ('pending', 'failed')
    AND (dep_check.total_parents = 0 OR dep_check.completed_parents = dep_check.total_parents)
    AND (ws.attempts < COALESCE(ws.retry_limit, 3))
    AND (
      last_failure.created_at IS NULL OR
      (ws.backoff_request_seconds IS NOT NULL AND ws.last_attempted_at IS NOT NULL AND
       ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second') <= NOW()) OR
      (ws.backoff_request_seconds IS NULL AND
       last_failure.created_at + (LEAST(power(2, COALESCE(ws.attempts, 1)) * interval '1 second', interval '30 seconds')) <= NOW())
    )
    THEN true
    ELSE false
  END as ready_for_execution,

  -- Timing Information
  last_failure.created_at as last_failure_at,
  CASE
    WHEN ws.backoff_request_seconds IS NOT NULL AND ws.last_attempted_at IS NOT NULL THEN
      ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second')
    WHEN last_failure.created_at IS NOT NULL THEN
      last_failure.created_at + (LEAST(power(2, COALESCE(ws.attempts, 1)) * interval '1 second', interval '30 seconds'))
    ELSE NULL
  END as next_retry_at,

  -- Dependency Context
  dep_check.total_parents,
  dep_check.completed_parents,

  -- Retry Context
  ws.attempts,
  COALESCE(ws.retry_limit, 3) as retry_limit,
  ws.backoff_request_seconds,
  ws.last_attempted_at

FROM tasker_workflow_steps ws
JOIN tasker_named_steps ns ON ns.named_step_id = ws.named_step_id

-- Current State Subquery
LEFT JOIN (
  SELECT DISTINCT ON (workflow_step_id)
    workflow_step_id, to_state
  FROM tasker_workflow_step_transitions
  ORDER BY workflow_step_id, created_at DESC
) current_state ON current_state.workflow_step_id = ws.workflow_step_id

-- Dependency Satisfaction Subquery
LEFT JOIN (
  SELECT
    child.workflow_step_id,
    COUNT(*) as total_parents,
    COUNT(CASE WHEN parent_state.to_state IN ('complete', 'resolved_manually') THEN 1 END) as completed_parents
  FROM tasker_workflow_step_edges dep
  JOIN tasker_workflow_steps child ON child.workflow_step_id = dep.to_step_id
  JOIN tasker_workflow_steps parent ON parent.workflow_step_id = dep.from_step_id
  LEFT JOIN (
    SELECT DISTINCT ON (workflow_step_id)
      workflow_step_id, to_state
    FROM tasker_workflow_step_transitions
    ORDER BY workflow_step_id, created_at DESC
  ) parent_state ON parent_state.workflow_step_id = parent.workflow_step_id
  GROUP BY child.workflow_step_id
) dep_check ON dep_check.workflow_step_id = ws.workflow_step_id

-- Last Failure Information
LEFT JOIN (
  SELECT DISTINCT ON (workflow_step_id)
    workflow_step_id, created_at
  FROM tasker_workflow_step_transitions
  WHERE to_state = 'failed'
  ORDER BY workflow_step_id, created_at DESC
) last_failure ON last_failure.workflow_step_id = ws.workflow_step_id
