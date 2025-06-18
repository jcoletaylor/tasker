-- Calculate Dependency Levels Function
-- Calculates the dependency level (depth) of each workflow step in a task
-- Uses recursive CTE to traverse the dependency graph and assign levels
-- Input: task_id
-- Output: workflow_step_id and its dependency level (0 = root, 1+ = depth from root)

CREATE OR REPLACE FUNCTION calculate_dependency_levels(input_task_id BIGINT)
RETURNS TABLE(
  workflow_step_id BIGINT,
  dependency_level INTEGER
) LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE dependency_levels AS (
    -- Base case: Find root nodes (steps with no dependencies)
    SELECT
      ws.workflow_step_id,
      0 as level
    FROM tasker_workflow_steps ws
    WHERE ws.task_id = input_task_id
      AND NOT EXISTS (
        SELECT 1
        FROM tasker_workflow_step_edges wse
        WHERE wse.to_step_id = ws.workflow_step_id
      )

    UNION ALL

    -- Recursive case: Find children of current level nodes
    SELECT
      wse.to_step_id as workflow_step_id,
      dl.level + 1 as level
    FROM dependency_levels dl
    JOIN tasker_workflow_step_edges wse ON wse.from_step_id = dl.workflow_step_id
    JOIN tasker_workflow_steps ws ON ws.workflow_step_id = wse.to_step_id
    WHERE ws.task_id = input_task_id
  )
  SELECT
    dl.workflow_step_id,
    MAX(dl.level) as dependency_level  -- Use MAX to handle multiple paths to same node
  FROM dependency_levels dl
  GROUP BY dl.workflow_step_id
  ORDER BY dependency_level, workflow_step_id;
END;
$$;
