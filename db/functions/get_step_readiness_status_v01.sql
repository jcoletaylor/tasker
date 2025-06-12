-- Step Readiness Status Function
-- Converts the view logic to a parameterized function for targeted queries
-- Input: Array of workflow_step_ids
-- Output: Readiness data for specified steps only

CREATE OR REPLACE FUNCTION get_step_readiness_status(input_task_id INTEGER, step_ids INTEGER[] DEFAULT NULL)
RETURNS TABLE(
  workflow_step_id INTEGER,
  task_id INTEGER,
  named_step_id INTEGER,
  name TEXT,
  current_state TEXT,
  dependencies_satisfied BOOLEAN,
  retry_eligible BOOLEAN,
  ready_for_execution BOOLEAN,
  last_failure_at TIMESTAMP,
  next_retry_at TIMESTAMP,
  total_parents INTEGER,
  completed_parents INTEGER,
  attempts INTEGER,
  retry_limit INTEGER,
  backoff_request_seconds INTEGER,
  last_attempted_at TIMESTAMP
) LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT
    ws.workflow_step_id,
    ws.task_id,
    ws.named_step_id,
    ns.name,

    -- Current State Information (optimized using most_recent flag)
    COALESCE(current_state.to_state, 'pending') as current_state,

    -- Dependency Analysis (calculated from direct joins)
    CASE
      WHEN dep_edges.to_step_id IS NULL THEN true  -- Root steps (no parents)
      WHEN COUNT(dep_edges.from_step_id) = 0 THEN true  -- Steps with zero dependencies
      WHEN COUNT(CASE WHEN parent_states.to_state IN ('complete', 'resolved_manually') THEN 1 END) = COUNT(dep_edges.from_step_id) THEN true
      ELSE false
    END as dependencies_satisfied,

    -- Simplified Retry & Backoff Analysis
    CASE
      WHEN ws.attempts >= COALESCE(ws.retry_limit, 3) THEN false
      WHEN ws.attempts > 0 AND ws.retryable = false THEN false
      WHEN last_failure.created_at IS NULL THEN true
      WHEN ws.backoff_request_seconds IS NOT NULL AND ws.last_attempted_at IS NOT NULL THEN
        ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second') <= NOW()
      WHEN last_failure.created_at IS NOT NULL THEN
        last_failure.created_at + (
          LEAST(power(2, COALESCE(ws.attempts, 1)) * interval '1 second', interval '30 seconds')
        ) <= NOW()
      ELSE true
    END as retry_eligible,

    -- Optimized Final Readiness Calculation
    CASE
      WHEN COALESCE(current_state.to_state, 'pending') IN ('pending', 'error')
      AND (dep_edges.to_step_id IS NULL OR
           COUNT(dep_edges.from_step_id) = 0 OR
           COUNT(CASE WHEN parent_states.to_state IN ('complete', 'resolved_manually') THEN 1 END) = COUNT(dep_edges.from_step_id))
      AND (ws.attempts < COALESCE(ws.retry_limit, 3))
      AND (ws.in_process = false)
      AND (
        (ws.backoff_request_seconds IS NOT NULL AND ws.last_attempted_at IS NOT NULL AND
         ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second') <= NOW()) OR
        (ws.backoff_request_seconds IS NULL AND last_failure.created_at IS NULL) OR
        (ws.backoff_request_seconds IS NULL AND last_failure.created_at IS NOT NULL AND
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

    -- Dependency Context (calculated from joins)
    COALESCE(COUNT(dep_edges.from_step_id), 0) as total_parents,
    COALESCE(COUNT(CASE WHEN parent_states.to_state IN ('complete', 'resolved_manually') THEN 1 END), 0) as completed_parents,

    -- Retry Context
    ws.attempts,
    COALESCE(ws.retry_limit, 3) as retry_limit,
    ws.backoff_request_seconds,
    ws.last_attempted_at

  FROM tasker_workflow_steps ws
  JOIN tasker_named_steps ns ON ns.named_step_id = ws.named_step_id

  -- OPTIMIZED: Current State using most_recent flag instead of DISTINCT ON
  LEFT JOIN tasker_workflow_step_transitions current_state
    ON current_state.workflow_step_id = ws.workflow_step_id
    AND current_state.most_recent = true

  -- OPTIMIZED: Dependency check using direct joins (no subquery)
  LEFT JOIN tasker_workflow_step_edges dep_edges
    ON dep_edges.to_step_id = ws.workflow_step_id
  LEFT JOIN tasker_workflow_step_transitions parent_states
    ON parent_states.workflow_step_id = dep_edges.from_step_id
    AND parent_states.most_recent = true

  -- OPTIMIZED: Last failure using index-optimized approach
  LEFT JOIN tasker_workflow_step_transitions last_failure
    ON last_failure.workflow_step_id = ws.workflow_step_id
    AND last_failure.to_state = 'error'
    AND last_failure.most_recent = true

  -- KEY PERFORMANCE IMPROVEMENT: Filter by task first, then optionally by step IDs
  WHERE ws.task_id = input_task_id
    AND (step_ids IS NULL OR ws.workflow_step_id = ANY(step_ids))
    AND (ws.processed = false OR ws.processed IS NULL)

  GROUP BY
    ws.workflow_step_id, ws.task_id, ws.named_step_id, ns.name,
    current_state.to_state, last_failure.created_at,
    ws.attempts, ws.retry_limit, ws.backoff_request_seconds, ws.last_attempted_at,
    ws.in_process, ws.processed, ws.retryable, dep_edges.to_step_id;
END;
$$;
