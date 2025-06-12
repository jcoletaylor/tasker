# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_06_12_000007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "tasker_annotation_types", primary_key: "annotation_type_id", id: :serial, force: :cascade do |t|
    t.string "name", limit: 64, null: false
    t.string "description", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "annotation_types_name_index"
    t.index ["name"], name: "annotation_types_name_unique", unique: true
  end

  create_table "tasker_dependent_system_object_maps", primary_key: "dependent_system_object_map_id", force: :cascade do |t|
    t.integer "dependent_system_one_id", null: false
    t.integer "dependent_system_two_id", null: false
    t.string "remote_id_one", limit: 128, null: false
    t.string "remote_id_two", limit: 128, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dependent_system_one_id", "dependent_system_two_id", "remote_id_one", "remote_id_two"], name: "dependent_system_object_maps_dependent_system_one_id_dependent_", unique: true
    t.index ["dependent_system_one_id"], name: "dependent_system_object_maps_dependent_system_one_id_index"
    t.index ["dependent_system_two_id"], name: "dependent_system_object_maps_dependent_system_two_id_index"
    t.index ["remote_id_one"], name: "dependent_system_object_maps_remote_id_one_index"
    t.index ["remote_id_two"], name: "dependent_system_object_maps_remote_id_two_index"
  end

  create_table "tasker_dependent_systems", primary_key: "dependent_system_id", id: :serial, force: :cascade do |t|
    t.string "name", limit: 64, null: false
    t.string "description", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "dependent_systems_name_index"
    t.index ["name"], name: "dependent_systems_name_unique", unique: true
  end

  create_table "tasker_named_steps", primary_key: "named_step_id", id: :serial, force: :cascade do |t|
    t.integer "dependent_system_id", null: false
    t.string "name", limit: 128, null: false
    t.string "description", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dependent_system_id", "name"], name: "named_step_by_system_uniq", unique: true
    t.index ["dependent_system_id"], name: "named_steps_dependent_system_id_index"
    t.index ["name"], name: "named_steps_name_index"
  end

  create_table "tasker_named_tasks", primary_key: "named_task_id", id: :serial, force: :cascade do |t|
    t.string "name", limit: 64, null: false
    t.string "description", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "named_tasks_name_index"
    t.index ["name"], name: "named_tasks_name_unique", unique: true
  end

  create_table "tasker_named_tasks_named_steps", id: :serial, force: :cascade do |t|
    t.integer "named_task_id", null: false
    t.integer "named_step_id", null: false
    t.boolean "skippable", default: false, null: false
    t.boolean "default_retryable", default: true, null: false
    t.integer "default_retry_limit", default: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["named_step_id"], name: "named_tasks_named_steps_named_step_id_index"
    t.index ["named_task_id", "named_step_id"], name: "named_tasks_steps_ids_unique", unique: true
    t.index ["named_task_id"], name: "named_tasks_named_steps_named_task_id_index"
  end

  create_table "tasker_task_annotations", primary_key: "task_annotation_id", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.integer "annotation_type_id", null: false
    t.jsonb "annotation"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["annotation"], name: "task_annotations_annotation_idx", using: :gin
    t.index ["annotation"], name: "task_annotations_annotation_idx1", opclass: :jsonb_path_ops, using: :gin
    t.index ["annotation_type_id"], name: "task_annotations_annotation_type_id_index"
    t.index ["task_id"], name: "task_annotations_task_id_index"
  end

  create_table "tasker_task_transitions", force: :cascade do |t|
    t.string "to_state", null: false
    t.string "from_state"
    t.jsonb "metadata", default: {}
    t.integer "sort_key", null: false
    t.boolean "most_recent", default: true, null: false
    t.bigint "task_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sort_key"], name: "index_tasker_task_transitions_on_sort_key"
    t.index ["task_id", "created_at"], name: "index_task_transitions_current_state"
    t.index ["task_id", "most_recent"], name: "idx_task_transitions_most_recent", where: "(most_recent = true)"
    t.index ["task_id", "most_recent"], name: "index_task_transitions_current_state_optimized", where: "(most_recent = true)"
    t.index ["task_id", "most_recent"], name: "index_tasker_task_transitions_on_task_id_and_most_recent", unique: true, where: "(most_recent = true)"
    t.index ["task_id", "sort_key"], name: "index_tasker_task_transitions_on_task_id_and_sort_key", unique: true
    t.index ["task_id"], name: "index_tasker_task_transitions_on_task_id"
  end

  create_table "tasker_tasks", primary_key: "task_id", force: :cascade do |t|
    t.integer "named_task_id", null: false
    t.boolean "complete", default: false, null: false
    t.datetime "requested_at", precision: nil, null: false
    t.string "initiator", limit: 128
    t.string "source_system", limit: 128
    t.string "reason", limit: 128
    t.json "bypass_steps"
    t.jsonb "tags"
    t.jsonb "context"
    t.string "identity_hash", limit: 128, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["complete", "created_at", "task_id"], name: "idx_tasks_completion_status_created"
    t.index ["context"], name: "tasks_context_idx", using: :gin
    t.index ["context"], name: "tasks_context_idx1", opclass: :jsonb_path_ops, using: :gin
    t.index ["identity_hash"], name: "index_tasks_on_identity_hash", unique: true
    t.index ["identity_hash"], name: "tasks_identity_hash_index"
    t.index ["named_task_id"], name: "tasks_named_task_id_index"
    t.index ["requested_at"], name: "tasks_requested_at_index"
    t.index ["source_system"], name: "tasks_source_system_index"
    t.index ["tags"], name: "tasks_tags_idx", using: :gin
    t.index ["tags"], name: "tasks_tags_idx1", opclass: :jsonb_path_ops, using: :gin
    t.index ["task_id", "complete"], name: "idx_tasks_active_workflow_summary", where: "((complete = false) OR (complete IS NULL))"
    t.index ["task_id"], name: "idx_tasks_active_operations", where: "((complete = false) OR (complete IS NULL))"
  end

  create_table "tasker_workflow_step_edges", force: :cascade do |t|
    t.bigint "from_step_id", null: false
    t.bigint "to_step_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_step_id", "to_step_id"], name: "index_step_edges_from_to_composite"
    t.index ["from_step_id"], name: "index_step_edges_from_step_for_children"
    t.index ["from_step_id"], name: "index_step_edges_parent_lookup"
    t.index ["from_step_id"], name: "index_tasker_workflow_step_edges_on_from_step_id"
    t.index ["to_step_id", "from_step_id"], name: "idx_workflow_step_edges_dependency_lookup"
    t.index ["to_step_id", "from_step_id"], name: "index_step_edges_dependency_pair"
    t.index ["to_step_id", "from_step_id"], name: "index_step_edges_to_from_composite"
    t.index ["to_step_id", "from_step_id"], name: "index_workflow_step_edges_dependency_lookup"
    t.index ["to_step_id"], name: "index_step_edges_child_lookup"
    t.index ["to_step_id"], name: "index_step_edges_to_step_for_parents"
    t.index ["to_step_id"], name: "index_tasker_workflow_step_edges_on_to_step_id"
  end

  create_table "tasker_workflow_step_transitions", force: :cascade do |t|
    t.string "to_state", null: false
    t.string "from_state"
    t.jsonb "metadata", default: {}
    t.integer "sort_key", null: false
    t.boolean "most_recent", default: true, null: false
    t.bigint "workflow_step_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sort_key"], name: "index_tasker_workflow_step_transitions_on_sort_key"
    t.index ["workflow_step_id", "created_at"], name: "index_step_transitions_for_current_state"
    t.index ["workflow_step_id", "most_recent", "created_at"], name: "index_step_transitions_current_errors", where: "(((to_state)::text = 'error'::text) AND (most_recent = true))"
    t.index ["workflow_step_id", "most_recent"], name: "idx_on_workflow_step_id_most_recent_97d5374ad6", unique: true, where: "(most_recent = true)"
    t.index ["workflow_step_id", "most_recent"], name: "idx_step_transitions_most_recent", where: "(most_recent = true)"
    t.index ["workflow_step_id", "most_recent"], name: "index_step_transitions_completed_parents", where: "(((to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) AND (most_recent = true))"
    t.index ["workflow_step_id", "most_recent"], name: "index_step_transitions_current_state_optimized", where: "(most_recent = true)"
    t.index ["workflow_step_id", "sort_key"], name: "idx_on_workflow_step_id_sort_key_4d476d7adb", unique: true
    t.index ["workflow_step_id", "to_state", "created_at"], name: "index_step_transitions_failures_with_timing", where: "((to_state)::text = 'failed'::text)"
    t.index ["workflow_step_id", "to_state"], name: "index_step_transitions_completed", where: "((to_state)::text = 'complete'::text)"
    t.index ["workflow_step_id"], name: "index_tasker_workflow_step_transitions_on_workflow_step_id"
  end

  create_table "tasker_workflow_steps", primary_key: "workflow_step_id", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.integer "named_step_id", null: false
    t.boolean "retryable", default: true, null: false
    t.integer "retry_limit", default: 3
    t.boolean "in_process", default: false, null: false
    t.boolean "processed", default: false, null: false
    t.datetime "processed_at", precision: nil
    t.integer "attempts"
    t.datetime "last_attempted_at", precision: nil
    t.integer "backoff_request_seconds"
    t.jsonb "inputs"
    t.jsonb "results"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "skippable", default: false, null: false
    t.index ["attempts", "retry_limit", "retryable"], name: "index_workflow_steps_retry_logic"
    t.index ["attempts", "retry_limit"], name: "index_workflow_steps_retry_status"
    t.index ["last_attempted_at", "backoff_request_seconds"], name: "index_workflow_steps_backoff_timing", where: "(backoff_request_seconds IS NOT NULL)"
    t.index ["last_attempted_at"], name: "workflow_steps_last_attempted_at_index"
    t.index ["named_step_id"], name: "workflow_steps_named_step_id_index"
    t.index ["processed_at"], name: "workflow_steps_processed_at_index"
    t.index ["task_id", "processed", "in_process"], name: "index_workflow_steps_processing_status"
    t.index ["task_id", "workflow_step_id"], name: "idx_workflow_steps_task_grouping_active", where: "((processed = false) OR (processed IS NULL))"
    t.index ["task_id", "workflow_step_id"], name: "index_workflow_steps_task_and_id"
    t.index ["task_id", "workflow_step_id"], name: "index_workflow_steps_task_and_step_id"
    t.index ["task_id", "workflow_step_id"], name: "index_workflow_steps_task_and_step_optimized"
    t.index ["task_id"], name: "index_workflow_steps_by_task"
    t.index ["task_id"], name: "index_workflow_steps_task_covering", include: ["workflow_step_id", "processed", "in_process", "attempts", "retry_limit"]
    t.index ["task_id"], name: "workflow_steps_task_id_index"
    t.index ["workflow_step_id", "task_id"], name: "idx_steps_active_operations", where: "((processed = false) OR (processed IS NULL))"
  end

  add_foreign_key "tasker_dependent_system_object_maps", "tasker_dependent_systems", column: "dependent_system_one_id", primary_key: "dependent_system_id", name: "dependent_system_object_maps_dependent_system_one_id_foreign"
  add_foreign_key "tasker_dependent_system_object_maps", "tasker_dependent_systems", column: "dependent_system_two_id", primary_key: "dependent_system_id", name: "dependent_system_object_maps_dependent_system_two_id_foreign"
  add_foreign_key "tasker_named_steps", "tasker_dependent_systems", column: "dependent_system_id", primary_key: "dependent_system_id", name: "named_steps_dependent_system_id_foreign"
  add_foreign_key "tasker_named_tasks_named_steps", "tasker_named_steps", column: "named_step_id", primary_key: "named_step_id", name: "named_tasks_named_steps_named_step_id_foreign"
  add_foreign_key "tasker_named_tasks_named_steps", "tasker_named_tasks", column: "named_task_id", primary_key: "named_task_id", name: "named_tasks_named_steps_named_task_id_foreign"
  add_foreign_key "tasker_task_annotations", "tasker_annotation_types", column: "annotation_type_id", primary_key: "annotation_type_id", name: "task_annotations_annotation_type_id_foreign"
  add_foreign_key "tasker_task_annotations", "tasker_tasks", column: "task_id", primary_key: "task_id", name: "task_annotations_task_id_foreign"
  add_foreign_key "tasker_task_transitions", "tasker_tasks", column: "task_id", primary_key: "task_id"
  add_foreign_key "tasker_tasks", "tasker_named_tasks", column: "named_task_id", primary_key: "named_task_id", name: "tasks_named_task_id_foreign"
  add_foreign_key "tasker_workflow_step_edges", "tasker_workflow_steps", column: "from_step_id", primary_key: "workflow_step_id"
  add_foreign_key "tasker_workflow_step_edges", "tasker_workflow_steps", column: "to_step_id", primary_key: "workflow_step_id"
  add_foreign_key "tasker_workflow_step_transitions", "tasker_workflow_steps", column: "workflow_step_id", primary_key: "workflow_step_id"
  add_foreign_key "tasker_workflow_steps", "tasker_named_steps", column: "named_step_id", primary_key: "named_step_id", name: "workflow_steps_named_step_id_foreign"
  add_foreign_key "tasker_workflow_steps", "tasker_tasks", column: "task_id", primary_key: "task_id", name: "workflow_steps_task_id_foreign"

  create_view "tasker_step_readiness_statuses", sql_definition: <<-SQL
      SELECT ws.workflow_step_id,
      ws.task_id,
      ws.named_step_id,
      ns.name,
      COALESCE(current_state.to_state, 'pending'::character varying) AS current_state,
          CASE
              WHEN (dep_edges.to_step_id IS NULL) THEN true
              WHEN (count(dep_edges.from_step_id) = 0) THEN true
              WHEN (count(
              CASE
                  WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
                  ELSE NULL::integer
              END) = count(dep_edges.from_step_id)) THEN true
              ELSE false
          END AS dependencies_satisfied,
          CASE
              WHEN (ws.attempts >= COALESCE(ws.retry_limit, 3)) THEN false
              WHEN ((ws.attempts > 0) AND (ws.retryable = false)) THEN false
              WHEN (last_failure.created_at IS NULL) THEN true
              WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * 'PT1S'::interval)) <= now())
              WHEN (last_failure.created_at IS NOT NULL) THEN ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * 'PT1S'::interval), 'PT30S'::interval)) <= now())
              ELSE true
          END AS retry_eligible,
          CASE
              WHEN (((COALESCE(current_state.to_state, 'pending'::character varying))::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[])) AND ((dep_edges.to_step_id IS NULL) OR (count(dep_edges.from_step_id) = 0) OR (count(
              CASE
                  WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
                  ELSE NULL::integer
              END) = count(dep_edges.from_step_id))) AND (ws.attempts < COALESCE(ws.retry_limit, 3)) AND (ws.in_process = false) AND (((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL) AND ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * 'PT1S'::interval)) <= now())) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NULL)) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NOT NULL) AND ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * 'PT1S'::interval), 'PT30S'::interval)) <= now())))) THEN true
              ELSE false
          END AS ready_for_execution,
      last_failure.created_at AS last_failure_at,
          CASE
              WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN (ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * 'PT1S'::interval))
              WHEN (last_failure.created_at IS NOT NULL) THEN (last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * 'PT1S'::interval), 'PT30S'::interval))
              ELSE NULL::timestamp without time zone
          END AS next_retry_at,
      COALESCE(count(dep_edges.from_step_id), (0)::bigint) AS total_parents,
      COALESCE(count(
          CASE
              WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
              ELSE NULL::integer
          END), (0)::bigint) AS completed_parents,
      ws.attempts,
      COALESCE(ws.retry_limit, 3) AS retry_limit,
      ws.backoff_request_seconds,
      ws.last_attempted_at
     FROM (((((tasker_workflow_steps ws
       JOIN tasker_named_steps ns ON ((ns.named_step_id = ws.named_step_id)))
       LEFT JOIN tasker_workflow_step_transitions current_state ON (((current_state.workflow_step_id = ws.workflow_step_id) AND (current_state.most_recent = true))))
       LEFT JOIN tasker_workflow_step_edges dep_edges ON ((dep_edges.to_step_id = ws.workflow_step_id)))
       LEFT JOIN tasker_workflow_step_transitions parent_states ON (((parent_states.workflow_step_id = dep_edges.from_step_id) AND (parent_states.most_recent = true))))
       LEFT JOIN tasker_workflow_step_transitions last_failure ON (((last_failure.workflow_step_id = ws.workflow_step_id) AND ((last_failure.to_state)::text = 'error'::text) AND (last_failure.most_recent = true))))
    WHERE ((ws.processed = false) OR (ws.processed IS NULL))
    GROUP BY ws.workflow_step_id, ws.task_id, ws.named_step_id, ns.name, current_state.to_state, last_failure.created_at, ws.attempts, ws.retry_limit, ws.backoff_request_seconds, ws.last_attempted_at, ws.in_process, ws.processed, ws.retryable, dep_edges.to_step_id;
  SQL
  create_view "tasker_task_execution_contexts", sql_definition: <<-SQL
      WITH step_aggregates AS (
           SELECT ws.task_id,
              count(*) AS total_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'pending'::text) THEN 1
                      ELSE NULL::integer
                  END) AS pending_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'in_progress'::text) THEN 1
                      ELSE NULL::integer
                  END) AS in_progress_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'complete'::text) THEN 1
                      ELSE NULL::integer
                  END) AS completed_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'error'::text) THEN 1
                      ELSE NULL::integer
                  END) AS failed_steps,
              count(
                  CASE
                      WHEN (srs.ready_for_execution = true) THEN 1
                      ELSE NULL::integer
                  END) AS ready_steps
             FROM (tasker_workflow_steps ws
               JOIN tasker_step_readiness_statuses srs ON ((srs.workflow_step_id = ws.workflow_step_id)))
            GROUP BY ws.task_id
          )
   SELECT t.task_id,
      t.named_task_id,
      COALESCE(task_state.to_state, 'pending'::character varying) AS status,
      COALESCE(step_aggregates.total_steps, (0)::bigint) AS total_steps,
      COALESCE(step_aggregates.pending_steps, (0)::bigint) AS pending_steps,
      COALESCE(step_aggregates.in_progress_steps, (0)::bigint) AS in_progress_steps,
      COALESCE(step_aggregates.completed_steps, (0)::bigint) AS completed_steps,
      COALESCE(step_aggregates.failed_steps, (0)::bigint) AS failed_steps,
      COALESCE(step_aggregates.ready_steps, (0)::bigint) AS ready_steps,
          CASE
              WHEN (COALESCE(step_aggregates.ready_steps, (0)::bigint) > 0) THEN 'has_ready_steps'::text
              WHEN (COALESCE(step_aggregates.in_progress_steps, (0)::bigint) > 0) THEN 'processing'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) = 0)) THEN 'blocked_by_failures'::text
              WHEN ((COALESCE(step_aggregates.completed_steps, (0)::bigint) = COALESCE(step_aggregates.total_steps, (0)::bigint)) AND (COALESCE(step_aggregates.total_steps, (0)::bigint) > 0)) THEN 'all_complete'::text
              ELSE 'waiting_for_dependencies'::text
          END AS execution_status,
          CASE
              WHEN (COALESCE(step_aggregates.ready_steps, (0)::bigint) > 0) THEN 'execute_ready_steps'::text
              WHEN (COALESCE(step_aggregates.in_progress_steps, (0)::bigint) > 0) THEN 'wait_for_completion'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) = 0)) THEN 'handle_failures'::text
              WHEN ((COALESCE(step_aggregates.completed_steps, (0)::bigint) = COALESCE(step_aggregates.total_steps, (0)::bigint)) AND (COALESCE(step_aggregates.total_steps, (0)::bigint) > 0)) THEN 'finalize_task'::text
              ELSE 'wait_for_dependencies'::text
          END AS recommended_action,
          CASE
              WHEN (COALESCE(step_aggregates.total_steps, (0)::bigint) = 0) THEN 0.0
              ELSE round((((COALESCE(step_aggregates.completed_steps, (0)::bigint))::numeric / (COALESCE(step_aggregates.total_steps, (1)::bigint))::numeric) * (100)::numeric), 2)
          END AS completion_percentage,
          CASE
              WHEN (COALESCE(step_aggregates.failed_steps, (0)::bigint) = 0) THEN 'healthy'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) > 0)) THEN 'recovering'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) = 0)) THEN 'blocked'::text
              ELSE 'unknown'::text
          END AS health_status
     FROM ((tasker_tasks t
       LEFT JOIN tasker_task_transitions task_state ON (((task_state.task_id = t.task_id) AND (task_state.most_recent = true))))
       LEFT JOIN step_aggregates ON ((step_aggregates.task_id = t.task_id)));
  SQL
  create_view "tasker_step_dag_relationships", sql_definition: <<-SQL
      SELECT ws.workflow_step_id,
      ws.task_id,
      ws.named_step_id,
      COALESCE(parent_data.parent_ids, '[]'::jsonb) AS parent_step_ids,
      COALESCE(child_data.child_ids, '[]'::jsonb) AS child_step_ids,
      COALESCE(parent_data.parent_count, (0)::bigint) AS parent_count,
      COALESCE(child_data.child_count, (0)::bigint) AS child_count,
          CASE
              WHEN (COALESCE(parent_data.parent_count, (0)::bigint) = 0) THEN true
              ELSE false
          END AS is_root_step,
          CASE
              WHEN (COALESCE(child_data.child_count, (0)::bigint) = 0) THEN true
              ELSE false
          END AS is_leaf_step,
      depth_info.min_depth_from_root
     FROM (((tasker_workflow_steps ws
       LEFT JOIN ( SELECT tasker_workflow_step_edges.to_step_id,
              jsonb_agg(tasker_workflow_step_edges.from_step_id ORDER BY tasker_workflow_step_edges.from_step_id) AS parent_ids,
              count(*) AS parent_count
             FROM tasker_workflow_step_edges
            GROUP BY tasker_workflow_step_edges.to_step_id) parent_data ON ((parent_data.to_step_id = ws.workflow_step_id)))
       LEFT JOIN ( SELECT tasker_workflow_step_edges.from_step_id,
              jsonb_agg(tasker_workflow_step_edges.to_step_id ORDER BY tasker_workflow_step_edges.to_step_id) AS child_ids,
              count(*) AS child_count
             FROM tasker_workflow_step_edges
            GROUP BY tasker_workflow_step_edges.from_step_id) child_data ON ((child_data.from_step_id = ws.workflow_step_id)))
       LEFT JOIN ( WITH RECURSIVE step_depths AS (
                   SELECT ws_inner.workflow_step_id,
                      0 AS depth_from_root,
                      ws_inner.task_id
                     FROM tasker_workflow_steps ws_inner
                    WHERE (NOT (EXISTS ( SELECT 1
                             FROM tasker_workflow_step_edges e
                            WHERE (e.to_step_id = ws_inner.workflow_step_id))))
                  UNION ALL
                   SELECT e.to_step_id,
                      (sd.depth_from_root + 1),
                      sd.task_id
                     FROM (step_depths sd
                       JOIN tasker_workflow_step_edges e ON ((e.from_step_id = sd.workflow_step_id)))
                    WHERE (sd.depth_from_root < 50)
                  )
           SELECT step_depths.workflow_step_id,
              min(step_depths.depth_from_root) AS min_depth_from_root
             FROM step_depths
            GROUP BY step_depths.workflow_step_id) depth_info ON ((depth_info.workflow_step_id = ws.workflow_step_id)));
  SQL
  create_view "tasker_active_step_readiness_statuses", sql_definition: <<-SQL
      SELECT ws.workflow_step_id,
      ws.task_id,
      ws.named_step_id,
      ns.name,
      COALESCE(current_state.to_state, 'pending'::character varying) AS current_state,
          CASE
              WHEN (dep_edges.to_step_id IS NULL) THEN true
              WHEN (count(dep_edges.from_step_id) = 0) THEN true
              WHEN (count(
              CASE
                  WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
                  ELSE NULL::integer
              END) = count(dep_edges.from_step_id)) THEN true
              ELSE false
          END AS dependencies_satisfied,
          CASE
              WHEN (ws.attempts >= COALESCE(ws.retry_limit, 3)) THEN false
              WHEN ((ws.attempts > 0) AND (ws.retryable = false)) THEN false
              WHEN (last_failure.created_at IS NULL) THEN true
              WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * 'PT1S'::interval)) <= now())
              WHEN (last_failure.created_at IS NOT NULL) THEN ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * 'PT1S'::interval), 'PT30S'::interval)) <= now())
              ELSE true
          END AS retry_eligible,
          CASE
              WHEN (((COALESCE(current_state.to_state, 'pending'::character varying))::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[])) AND ((dep_edges.to_step_id IS NULL) OR (count(dep_edges.from_step_id) = 0) OR (count(
              CASE
                  WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
                  ELSE NULL::integer
              END) = count(dep_edges.from_step_id))) AND (ws.attempts < COALESCE(ws.retry_limit, 3)) AND (ws.in_process = false) AND (((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL) AND ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * 'PT1S'::interval)) <= now())) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NULL)) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NOT NULL) AND ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * 'PT1S'::interval), 'PT30S'::interval)) <= now())))) THEN true
              ELSE false
          END AS ready_for_execution,
      last_failure.created_at AS last_failure_at,
          CASE
              WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN (ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * 'PT1S'::interval))
              WHEN (last_failure.created_at IS NOT NULL) THEN (last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * 'PT1S'::interval), 'PT30S'::interval))
              ELSE NULL::timestamp without time zone
          END AS next_retry_at,
      COALESCE(count(dep_edges.from_step_id), (0)::bigint) AS total_parents,
      COALESCE(count(
          CASE
              WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
              ELSE NULL::integer
          END), (0)::bigint) AS completed_parents,
      ws.attempts,
      COALESCE(ws.retry_limit, 3) AS retry_limit,
      ws.backoff_request_seconds,
      ws.last_attempted_at
     FROM ((((((tasker_workflow_steps ws
       JOIN tasker_named_steps ns ON ((ns.named_step_id = ws.named_step_id)))
       JOIN tasker_tasks t ON (((t.task_id = ws.task_id) AND ((t.complete = false) OR (t.complete IS NULL)))))
       LEFT JOIN tasker_workflow_step_transitions current_state ON (((current_state.workflow_step_id = ws.workflow_step_id) AND (current_state.most_recent = true))))
       LEFT JOIN tasker_workflow_step_edges dep_edges ON ((dep_edges.to_step_id = ws.workflow_step_id)))
       LEFT JOIN tasker_workflow_step_transitions parent_states ON (((parent_states.workflow_step_id = dep_edges.from_step_id) AND (parent_states.most_recent = true))))
       LEFT JOIN tasker_workflow_step_transitions last_failure ON (((last_failure.workflow_step_id = ws.workflow_step_id) AND ((last_failure.to_state)::text = 'error'::text) AND (last_failure.most_recent = true))))
    WHERE ((ws.processed = false) OR (ws.processed IS NULL))
    GROUP BY ws.workflow_step_id, ws.task_id, ws.named_step_id, ns.name, current_state.to_state, last_failure.created_at, ws.attempts, ws.retry_limit, ws.backoff_request_seconds, ws.last_attempted_at, ws.in_process, ws.processed, ws.retryable, dep_edges.to_step_id;
  SQL
  create_view "tasker_active_task_execution_contexts", sql_definition: <<-SQL
      WITH active_step_aggregates AS (
           SELECT ws.task_id,
              count(*) AS total_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'pending'::text) THEN 1
                      ELSE NULL::integer
                  END) AS pending_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'in_progress'::text) THEN 1
                      ELSE NULL::integer
                  END) AS in_progress_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'complete'::text) THEN 1
                      ELSE NULL::integer
                  END) AS completed_steps,
              count(
                  CASE
                      WHEN ((srs.current_state)::text = 'error'::text) THEN 1
                      ELSE NULL::integer
                  END) AS failed_steps,
              count(
                  CASE
                      WHEN (srs.ready_for_execution = true) THEN 1
                      ELSE NULL::integer
                  END) AS ready_steps
             FROM ((tasker_workflow_steps ws
               JOIN tasker_active_step_readiness_statuses srs ON ((srs.workflow_step_id = ws.workflow_step_id)))
               JOIN tasker_tasks t_1 ON (((t_1.task_id = ws.task_id) AND ((t_1.complete = false) OR (t_1.complete IS NULL)))))
            GROUP BY ws.task_id
          )
   SELECT t.task_id,
      t.named_task_id,
      COALESCE(task_state.to_state, 'pending'::character varying) AS status,
      COALESCE(step_aggregates.total_steps, (0)::bigint) AS total_steps,
      COALESCE(step_aggregates.pending_steps, (0)::bigint) AS pending_steps,
      COALESCE(step_aggregates.in_progress_steps, (0)::bigint) AS in_progress_steps,
      COALESCE(step_aggregates.completed_steps, (0)::bigint) AS completed_steps,
      COALESCE(step_aggregates.failed_steps, (0)::bigint) AS failed_steps,
      COALESCE(step_aggregates.ready_steps, (0)::bigint) AS ready_steps,
          CASE
              WHEN (COALESCE(step_aggregates.ready_steps, (0)::bigint) > 0) THEN 'has_ready_steps'::text
              WHEN (COALESCE(step_aggregates.in_progress_steps, (0)::bigint) > 0) THEN 'processing'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) = 0)) THEN 'blocked_by_failures'::text
              WHEN ((COALESCE(step_aggregates.completed_steps, (0)::bigint) = COALESCE(step_aggregates.total_steps, (0)::bigint)) AND (COALESCE(step_aggregates.total_steps, (0)::bigint) > 0)) THEN 'all_complete'::text
              ELSE 'waiting_for_dependencies'::text
          END AS execution_status,
          CASE
              WHEN (COALESCE(step_aggregates.ready_steps, (0)::bigint) > 0) THEN 'execute_ready_steps'::text
              WHEN (COALESCE(step_aggregates.in_progress_steps, (0)::bigint) > 0) THEN 'wait_for_completion'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) = 0)) THEN 'handle_failures'::text
              WHEN ((COALESCE(step_aggregates.completed_steps, (0)::bigint) = COALESCE(step_aggregates.total_steps, (0)::bigint)) AND (COALESCE(step_aggregates.total_steps, (0)::bigint) > 0)) THEN 'finalize_task'::text
              ELSE 'wait_for_dependencies'::text
          END AS recommended_action,
          CASE
              WHEN (COALESCE(step_aggregates.total_steps, (0)::bigint) = 0) THEN 0.0
              ELSE round((((COALESCE(step_aggregates.completed_steps, (0)::bigint))::numeric / (COALESCE(step_aggregates.total_steps, (1)::bigint))::numeric) * (100)::numeric), 2)
          END AS completion_percentage,
          CASE
              WHEN (COALESCE(step_aggregates.failed_steps, (0)::bigint) = 0) THEN 'healthy'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) > 0)) THEN 'recovering'::text
              WHEN ((COALESCE(step_aggregates.failed_steps, (0)::bigint) > 0) AND (COALESCE(step_aggregates.ready_steps, (0)::bigint) = 0)) THEN 'blocked'::text
              ELSE 'unknown'::text
          END AS health_status
     FROM ((tasker_tasks t
       LEFT JOIN tasker_task_transitions task_state ON (((task_state.task_id = t.task_id) AND (task_state.most_recent = true))))
       LEFT JOIN active_step_aggregates step_aggregates ON ((step_aggregates.task_id = t.task_id)))
    WHERE ((t.complete = false) OR (t.complete IS NULL));
  SQL
  create_view "tasker_task_workflow_summaries", sql_definition: <<-SQL
      SELECT atec.task_id,
      atec.named_task_id,
      atec.status,
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
      workflow_analysis.root_step_ids,
      workflow_analysis.root_step_count,
      workflow_analysis.ready_step_ids,
      workflow_analysis.blocked_step_ids,
      workflow_analysis.blocking_reasons,
      workflow_analysis.max_dependency_depth,
      workflow_analysis.parallel_branches,
          CASE
              WHEN ((atec.ready_steps > 0) AND (atec.failed_steps = 0)) THEN 'optimal'::text
              WHEN ((atec.ready_steps > 0) AND (atec.failed_steps > 0)) THEN 'recovering'::text
              WHEN ((atec.ready_steps = 0) AND (atec.in_progress_steps > 0)) THEN 'processing'::text
              WHEN ((atec.ready_steps = 0) AND (atec.failed_steps > 0)) THEN 'blocked'::text
              ELSE 'waiting'::text
          END AS workflow_efficiency,
          CASE
              WHEN (atec.ready_steps > 5) THEN 'high_parallelism'::text
              WHEN (atec.ready_steps > 1) THEN 'moderate_parallelism'::text
              WHEN (atec.ready_steps = 1) THEN 'sequential_only'::text
              ELSE 'no_ready_work'::text
          END AS parallelism_potential
     FROM (tasker_active_task_execution_contexts atec
       LEFT JOIN ( SELECT asrs.task_id,
              jsonb_agg(
                  CASE
                      WHEN (asrs.total_parents = 0) THEN asrs.workflow_step_id
                      ELSE NULL::bigint
                  END) FILTER (WHERE (asrs.total_parents = 0)) AS root_step_ids,
              count(*) FILTER (WHERE (asrs.total_parents = 0)) AS root_step_count,
              jsonb_agg(
                  CASE
                      WHEN (asrs.ready_for_execution = true) THEN asrs.workflow_step_id
                      ELSE NULL::bigint
                  END) FILTER (WHERE (asrs.ready_for_execution = true)) AS ready_step_ids,
              jsonb_agg(
                  CASE
                      WHEN ((asrs.ready_for_execution = false) AND ((asrs.current_state)::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[]))) THEN asrs.workflow_step_id
                      ELSE NULL::bigint
                  END) FILTER (WHERE ((asrs.ready_for_execution = false) AND ((asrs.current_state)::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[])))) AS blocked_step_ids,
              jsonb_agg(
                  CASE
                      WHEN ((asrs.ready_for_execution = false) AND ((asrs.current_state)::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[]))) THEN
                      CASE
                          WHEN (asrs.dependencies_satisfied = false) THEN 'dependencies_not_satisfied'::text
                          WHEN (asrs.retry_eligible = false) THEN 'retry_not_eligible'::text
                          WHEN ((asrs.current_state)::text <> ALL ((ARRAY['pending'::character varying, 'error'::character varying])::text[])) THEN 'invalid_state'::text
                          ELSE 'unknown'::text
                      END
                      ELSE NULL::text
                  END) FILTER (WHERE ((asrs.ready_for_execution = false) AND ((asrs.current_state)::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[])))) AS blocking_reasons,
              max(asrs.total_parents) AS max_dependency_depth,
              count(DISTINCT asrs.total_parents) AS parallel_branches
             FROM tasker_active_step_readiness_statuses asrs
            GROUP BY asrs.task_id) workflow_analysis ON ((workflow_analysis.task_id = atec.task_id)));
  SQL
end
