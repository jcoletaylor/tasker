SELECT
  ws.workflow_step_id,
  ws.task_id,
  ws.named_step_id,

  -- Parent/Child relationship data (pre-calculated as JSONB arrays)
  COALESCE(parent_data.parent_ids, '[]'::jsonb) as parent_step_ids,
  COALESCE(child_data.child_ids, '[]'::jsonb) as child_step_ids,
  COALESCE(parent_data.parent_count, 0) as parent_count,
  COALESCE(child_data.child_count, 0) as child_count,

  -- DAG position information
  CASE WHEN COALESCE(parent_data.parent_count, 0) = 0 THEN true ELSE false END as is_root_step,
  CASE WHEN COALESCE(child_data.child_count, 0) = 0 THEN true ELSE false END as is_leaf_step,

  -- Depth calculation for DAG traversal optimization
  depth_info.min_depth_from_root

FROM tasker_workflow_steps ws

LEFT JOIN (
  SELECT
    to_step_id,
    jsonb_agg(from_step_id ORDER BY from_step_id) as parent_ids,
    count(*) as parent_count
  FROM tasker_workflow_step_edges
  GROUP BY to_step_id
) parent_data ON parent_data.to_step_id = ws.workflow_step_id

LEFT JOIN (
  SELECT
    from_step_id,
    jsonb_agg(to_step_id ORDER BY to_step_id) as child_ids,
    count(*) as child_count
  FROM tasker_workflow_step_edges
  GROUP BY from_step_id
) child_data ON child_data.from_step_id = ws.workflow_step_id

LEFT JOIN (
  -- Recursive CTE for depth calculation (PostgreSQL-specific)
  WITH RECURSIVE step_depths AS (
    -- Base case: root steps (no parents)
    SELECT
      ws_inner.workflow_step_id,
      0 as depth_from_root,
      ws_inner.task_id
    FROM tasker_workflow_steps ws_inner
    WHERE NOT EXISTS (
      SELECT 1 FROM tasker_workflow_step_edges e
      WHERE e.to_step_id = ws_inner.workflow_step_id
    )

    UNION ALL

    -- Recursive case: steps with parents
    SELECT
      e.to_step_id,
      sd.depth_from_root + 1,
      sd.task_id
    FROM step_depths sd
    JOIN tasker_workflow_step_edges e ON e.from_step_id = sd.workflow_step_id
    WHERE sd.depth_from_root < 50 -- Prevent infinite recursion
  )
  SELECT
    workflow_step_id,
    MIN(depth_from_root) as min_depth_from_root
  FROM step_depths
  GROUP BY workflow_step_id
) depth_info ON depth_info.workflow_step_id = ws.workflow_step_id
