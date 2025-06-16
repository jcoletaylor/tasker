-- Task Workflow Summary View - Redesigned for Scalable Architecture
-- This view provides enhanced workflow analysis for active tasks only
-- Built on top of optimized active views for maximum performance

SELECT
  atec.task_id,
  atec.named_task_id,
  atec.status,

  -- Core execution metrics (from active task execution context)
  atec.total_steps,
  atec.pending_steps,
  atec.in_progress_steps,
  atec.completed_steps,
  atec.failed_steps,
  atec.ready_steps,
  atec.execution_status,
  atec.recommended_action,
  atec.completion_percentage,
  atec.health_status,

  -- Enhanced workflow analysis using active step data
  workflow_analysis.root_step_ids,
  workflow_analysis.root_step_count,
  workflow_analysis.ready_step_ids,
  workflow_analysis.blocked_step_ids,
  workflow_analysis.blocking_reasons,

  -- Workflow complexity metrics
  workflow_analysis.max_dependency_depth,
  workflow_analysis.parallel_branches,

  -- Workflow insights (descriptive, not prescriptive)
  CASE
    WHEN atec.ready_steps > 0 AND atec.failed_steps = 0 THEN 'optimal'
    WHEN atec.ready_steps > 0 AND atec.failed_steps > 0 THEN 'recovering'
    WHEN atec.ready_steps = 0 AND atec.in_progress_steps > 0 THEN 'processing'
    WHEN atec.ready_steps = 0 AND atec.failed_steps > 0 THEN 'blocked'
    ELSE 'waiting'
  END as workflow_efficiency,

  -- Parallelism potential (insight, not directive)
  CASE
    WHEN atec.ready_steps > 5 THEN 'high_parallelism'
    WHEN atec.ready_steps > 1 THEN 'moderate_parallelism'
    WHEN atec.ready_steps = 1 THEN 'sequential_only'
    ELSE 'no_ready_work'
  END as parallelism_potential

FROM tasker_active_task_execution_contexts atec

-- PERFORMANCE OPTIMIZATION: Single CTE for all step analysis on active data only
LEFT JOIN (
  SELECT
    asrs.task_id,

    -- Root steps analysis
    jsonb_agg(
      CASE WHEN asrs.total_parents = 0 THEN asrs.workflow_step_id END
    ) FILTER (WHERE asrs.total_parents = 0) as root_step_ids,
    COUNT(*) FILTER (WHERE asrs.total_parents = 0) as root_step_count,

    -- Ready steps analysis
    jsonb_agg(
      CASE WHEN asrs.ready_for_execution = true THEN asrs.workflow_step_id END
    ) FILTER (WHERE asrs.ready_for_execution = true) as ready_step_ids,

    -- Blocked steps analysis
    jsonb_agg(
      CASE WHEN asrs.ready_for_execution = false AND asrs.current_state IN ('pending', 'error')
           THEN asrs.workflow_step_id END
    ) FILTER (WHERE asrs.ready_for_execution = false AND asrs.current_state IN ('pending', 'error')) as blocked_step_ids,

    jsonb_agg(
      CASE WHEN asrs.ready_for_execution = false AND asrs.current_state IN ('pending', 'error') THEN
        CASE
          WHEN asrs.dependencies_satisfied = false THEN 'dependencies_not_satisfied'
          WHEN asrs.retry_eligible = false THEN 'retry_not_eligible'
          WHEN asrs.current_state NOT IN ('pending', 'error') THEN 'invalid_state'
          ELSE 'unknown'
        END
      END
    ) FILTER (WHERE asrs.ready_for_execution = false AND asrs.current_state IN ('pending', 'error')) as blocking_reasons,

    -- Workflow complexity metrics
    MAX(asrs.total_parents) as max_dependency_depth,
    COUNT(DISTINCT asrs.total_parents) as parallel_branches

  FROM tasker_active_step_readiness_statuses asrs
  GROUP BY asrs.task_id
) workflow_analysis ON workflow_analysis.task_id = atec.task_id
