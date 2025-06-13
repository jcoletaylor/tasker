SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: get_step_readiness_status(bigint, bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_step_readiness_status(input_task_id bigint, step_ids bigint[] DEFAULT NULL::bigint[]) RETURNS TABLE(workflow_step_id bigint, task_id bigint, named_step_id integer, name text, current_state text, dependencies_satisfied boolean, retry_eligible boolean, ready_for_execution boolean, last_failure_at timestamp without time zone, next_retry_at timestamp without time zone, total_parents integer, completed_parents integer, attempts integer, retry_limit integer, backoff_request_seconds integer, last_attempted_at timestamp without time zone)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    ws.workflow_step_id,
    ws.task_id,
    ws.named_step_id,
    ns.name::TEXT,

    -- Current State Information (optimized using most_recent flag)
    COALESCE(current_state.to_state, 'pending')::TEXT as current_state,

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
    COALESCE(COUNT(dep_edges.from_step_id), 0)::INTEGER as total_parents,
    COALESCE(COUNT(CASE WHEN parent_states.to_state IN ('complete', 'resolved_manually') THEN 1 END), 0)::INTEGER as completed_parents,

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


--
-- Name: get_step_readiness_status_batch(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_step_readiness_status_batch(input_task_ids bigint[]) RETURNS TABLE(workflow_step_id bigint, task_id bigint, named_step_id integer, name text, current_state text, dependencies_satisfied boolean, retry_eligible boolean, ready_for_execution boolean, last_failure_at timestamp without time zone, next_retry_at timestamp without time zone, total_parents integer, completed_parents integer, attempts integer, retry_limit integer, backoff_request_seconds integer, last_attempted_at timestamp without time zone)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    ws.workflow_step_id,
    ws.task_id,
    ws.named_step_id,
    ns.name::TEXT,

    -- Current State Information (optimized using most_recent flag)
    COALESCE(current_state.to_state, 'pending')::TEXT as current_state,

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
    COALESCE(COUNT(dep_edges.from_step_id), 0)::INTEGER as total_parents,
    COALESCE(COUNT(CASE WHEN parent_states.to_state IN ('complete', 'resolved_manually') THEN 1 END), 0)::INTEGER as completed_parents,

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

  -- KEY PERFORMANCE IMPROVEMENT: Filter by multiple tasks at once
  WHERE ws.task_id = ANY(input_task_ids)
    AND (ws.processed = false OR ws.processed IS NULL)

  GROUP BY
    ws.workflow_step_id, ws.task_id, ws.named_step_id, ns.name,
    current_state.to_state, last_failure.created_at,
    ws.attempts, ws.retry_limit, ws.backoff_request_seconds, ws.last_attempted_at,
    ws.in_process, ws.processed, ws.retryable, dep_edges.to_step_id

  -- IMPORTANT: Order by task_id, then workflow_step_id for consistent grouping
  ORDER BY ws.task_id, ws.workflow_step_id;
END;
$$;


--
-- Name: get_task_execution_context(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_task_execution_context(input_task_id bigint) RETURNS TABLE(task_id bigint, named_task_id integer, status text, total_steps bigint, pending_steps bigint, in_progress_steps bigint, completed_steps bigint, failed_steps bigint, ready_steps bigint, execution_status text, recommended_action text, completion_percentage numeric, health_status text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  -- Use the step readiness function to get step data, then aggregate
  -- The step readiness function handles the case where no steps exist
  RETURN QUERY
  WITH step_data AS (
    SELECT * FROM get_step_readiness_status(input_task_id, NULL)
  ),
  task_info AS (
    SELECT
      t.task_id,
      t.named_task_id,
      COALESCE(task_state.to_state, 'pending')::TEXT as current_status
    FROM tasker_tasks t
    LEFT JOIN tasker_task_transitions task_state
      ON task_state.task_id = t.task_id
      AND task_state.most_recent = true
    WHERE t.task_id = input_task_id
  ),
  aggregated_stats AS (
    SELECT
      COUNT(*) as total_steps,
      COUNT(CASE WHEN sd.current_state = 'pending' THEN 1 END) as pending_steps,
      COUNT(CASE WHEN sd.current_state = 'in_progress' THEN 1 END) as in_progress_steps,
      COUNT(CASE WHEN sd.current_state IN ('complete', 'resolved_manually') THEN 1 END) as completed_steps,
      COUNT(CASE WHEN sd.current_state = 'error' THEN 1 END) as failed_steps,
      COUNT(CASE WHEN sd.ready_for_execution = true THEN 1 END) as ready_steps
    FROM step_data sd
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
  CROSS JOIN aggregated_stats ast;
END;
$$;


--
-- Name: get_task_execution_contexts_batch(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_task_execution_contexts_batch(input_task_ids bigint[]) RETURNS TABLE(task_id bigint, named_task_id integer, status text, total_steps bigint, pending_steps bigint, in_progress_steps bigint, completed_steps bigint, failed_steps bigint, ready_steps bigint, execution_status text, recommended_action text, completion_percentage numeric, health_status text)
    LANGUAGE plpgsql STABLE
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tasker_named_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_named_steps (
    named_step_id integer NOT NULL,
    dependent_system_id integer NOT NULL,
    name character varying(128) NOT NULL,
    description character varying(255),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_tasks (
    task_id bigint NOT NULL,
    named_task_id integer NOT NULL,
    complete boolean DEFAULT false NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    initiator character varying(128),
    source_system character varying(128),
    reason character varying(128),
    bypass_steps json,
    tags jsonb,
    context jsonb,
    identity_hash character varying(128) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_workflow_step_edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_workflow_step_edges (
    id bigint NOT NULL,
    from_step_id bigint NOT NULL,
    to_step_id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_workflow_step_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_workflow_step_transitions (
    id bigint NOT NULL,
    to_state character varying NOT NULL,
    from_state character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    sort_key integer NOT NULL,
    most_recent boolean DEFAULT true NOT NULL,
    workflow_step_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_workflow_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_workflow_steps (
    workflow_step_id bigint NOT NULL,
    task_id bigint NOT NULL,
    named_step_id integer NOT NULL,
    retryable boolean DEFAULT true NOT NULL,
    retry_limit integer DEFAULT 3,
    in_process boolean DEFAULT false NOT NULL,
    processed boolean DEFAULT false NOT NULL,
    processed_at timestamp without time zone,
    attempts integer,
    last_attempted_at timestamp without time zone,
    backoff_request_seconds integer,
    inputs jsonb,
    results jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    skippable boolean DEFAULT false NOT NULL
);


--
-- Name: tasker_active_step_readiness_statuses; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tasker_active_step_readiness_statuses AS
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
            WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * '00:00:01'::interval)) <= now())
            WHEN (last_failure.created_at IS NOT NULL) THEN ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * '00:00:01'::interval), '00:00:30'::interval)) <= now())
            ELSE true
        END AS retry_eligible,
        CASE
            WHEN (((COALESCE(current_state.to_state, 'pending'::character varying))::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[])) AND ((dep_edges.to_step_id IS NULL) OR (count(dep_edges.from_step_id) = 0) OR (count(
            CASE
                WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
                ELSE NULL::integer
            END) = count(dep_edges.from_step_id))) AND (ws.attempts < COALESCE(ws.retry_limit, 3)) AND (ws.in_process = false) AND (((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL) AND ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * '00:00:01'::interval)) <= now())) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NULL)) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NOT NULL) AND ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * '00:00:01'::interval), '00:00:30'::interval)) <= now())))) THEN true
            ELSE false
        END AS ready_for_execution,
    last_failure.created_at AS last_failure_at,
        CASE
            WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN (ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * '00:00:01'::interval))
            WHEN (last_failure.created_at IS NOT NULL) THEN (last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * '00:00:01'::interval), '00:00:30'::interval))
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
   FROM ((((((public.tasker_workflow_steps ws
     JOIN public.tasker_named_steps ns ON ((ns.named_step_id = ws.named_step_id)))
     JOIN public.tasker_tasks t ON (((t.task_id = ws.task_id) AND ((t.complete = false) OR (t.complete IS NULL)))))
     LEFT JOIN public.tasker_workflow_step_transitions current_state ON (((current_state.workflow_step_id = ws.workflow_step_id) AND (current_state.most_recent = true))))
     LEFT JOIN public.tasker_workflow_step_edges dep_edges ON ((dep_edges.to_step_id = ws.workflow_step_id)))
     LEFT JOIN public.tasker_workflow_step_transitions parent_states ON (((parent_states.workflow_step_id = dep_edges.from_step_id) AND (parent_states.most_recent = true))))
     LEFT JOIN public.tasker_workflow_step_transitions last_failure ON (((last_failure.workflow_step_id = ws.workflow_step_id) AND ((last_failure.to_state)::text = 'error'::text) AND (last_failure.most_recent = true))))
  WHERE ((ws.processed = false) OR (ws.processed IS NULL))
  GROUP BY ws.workflow_step_id, ws.task_id, ws.named_step_id, ns.name, current_state.to_state, last_failure.created_at, ws.attempts, ws.retry_limit, ws.backoff_request_seconds, ws.last_attempted_at, ws.in_process, ws.processed, ws.retryable, dep_edges.to_step_id;


--
-- Name: tasker_task_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_task_transitions (
    id bigint NOT NULL,
    to_state character varying NOT NULL,
    from_state character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    sort_key integer NOT NULL,
    most_recent boolean DEFAULT true NOT NULL,
    task_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_active_task_execution_contexts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tasker_active_task_execution_contexts AS
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
           FROM ((public.tasker_workflow_steps ws
             JOIN public.tasker_active_step_readiness_statuses srs ON ((srs.workflow_step_id = ws.workflow_step_id)))
             JOIN public.tasker_tasks t_1 ON (((t_1.task_id = ws.task_id) AND ((t_1.complete = false) OR (t_1.complete IS NULL)))))
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
   FROM ((public.tasker_tasks t
     LEFT JOIN public.tasker_task_transitions task_state ON (((task_state.task_id = t.task_id) AND (task_state.most_recent = true))))
     LEFT JOIN active_step_aggregates step_aggregates ON ((step_aggregates.task_id = t.task_id)))
  WHERE ((t.complete = false) OR (t.complete IS NULL));


--
-- Name: tasker_annotation_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_annotation_types (
    annotation_type_id integer NOT NULL,
    name character varying(64) NOT NULL,
    description character varying(255),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_annotation_types_annotation_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_annotation_types_annotation_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_annotation_types_annotation_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_annotation_types_annotation_type_id_seq OWNED BY public.tasker_annotation_types.annotation_type_id;


--
-- Name: tasker_dependent_system_object_maps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_dependent_system_object_maps (
    dependent_system_object_map_id bigint NOT NULL,
    dependent_system_one_id integer NOT NULL,
    dependent_system_two_id integer NOT NULL,
    remote_id_one character varying(128) NOT NULL,
    remote_id_two character varying(128) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_dependent_system_objec_dependent_system_object_map_i_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_dependent_system_objec_dependent_system_object_map_i_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_dependent_system_objec_dependent_system_object_map_i_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_dependent_system_objec_dependent_system_object_map_i_seq OWNED BY public.tasker_dependent_system_object_maps.dependent_system_object_map_id;


--
-- Name: tasker_dependent_systems; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_dependent_systems (
    dependent_system_id integer NOT NULL,
    name character varying(64) NOT NULL,
    description character varying(255),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_dependent_systems_dependent_system_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_dependent_systems_dependent_system_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_dependent_systems_dependent_system_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_dependent_systems_dependent_system_id_seq OWNED BY public.tasker_dependent_systems.dependent_system_id;


--
-- Name: tasker_named_steps_named_step_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_named_steps_named_step_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_named_steps_named_step_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_named_steps_named_step_id_seq OWNED BY public.tasker_named_steps.named_step_id;


--
-- Name: tasker_named_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_named_tasks (
    named_task_id integer NOT NULL,
    name character varying(64) NOT NULL,
    description character varying(255),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_named_tasks_named_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_named_tasks_named_steps (
    id integer NOT NULL,
    named_task_id integer NOT NULL,
    named_step_id integer NOT NULL,
    skippable boolean DEFAULT false NOT NULL,
    default_retryable boolean DEFAULT true NOT NULL,
    default_retry_limit integer DEFAULT 3 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_named_tasks_named_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_named_tasks_named_steps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_named_tasks_named_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_named_tasks_named_steps_id_seq OWNED BY public.tasker_named_tasks_named_steps.id;


--
-- Name: tasker_named_tasks_named_task_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_named_tasks_named_task_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_named_tasks_named_task_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_named_tasks_named_task_id_seq OWNED BY public.tasker_named_tasks.named_task_id;


--
-- Name: tasker_step_dag_relationships; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tasker_step_dag_relationships AS
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
   FROM (((public.tasker_workflow_steps ws
     LEFT JOIN ( SELECT tasker_workflow_step_edges.to_step_id,
            jsonb_agg(tasker_workflow_step_edges.from_step_id ORDER BY tasker_workflow_step_edges.from_step_id) AS parent_ids,
            count(*) AS parent_count
           FROM public.tasker_workflow_step_edges
          GROUP BY tasker_workflow_step_edges.to_step_id) parent_data ON ((parent_data.to_step_id = ws.workflow_step_id)))
     LEFT JOIN ( SELECT tasker_workflow_step_edges.from_step_id,
            jsonb_agg(tasker_workflow_step_edges.to_step_id ORDER BY tasker_workflow_step_edges.to_step_id) AS child_ids,
            count(*) AS child_count
           FROM public.tasker_workflow_step_edges
          GROUP BY tasker_workflow_step_edges.from_step_id) child_data ON ((child_data.from_step_id = ws.workflow_step_id)))
     LEFT JOIN ( WITH RECURSIVE step_depths AS (
                 SELECT ws_inner.workflow_step_id,
                    0 AS depth_from_root,
                    ws_inner.task_id
                   FROM public.tasker_workflow_steps ws_inner
                  WHERE (NOT (EXISTS ( SELECT 1
                           FROM public.tasker_workflow_step_edges e
                          WHERE (e.to_step_id = ws_inner.workflow_step_id))))
                UNION ALL
                 SELECT e.to_step_id,
                    (sd.depth_from_root + 1),
                    sd.task_id
                   FROM (step_depths sd
                     JOIN public.tasker_workflow_step_edges e ON ((e.from_step_id = sd.workflow_step_id)))
                  WHERE (sd.depth_from_root < 50)
                )
         SELECT step_depths.workflow_step_id,
            min(step_depths.depth_from_root) AS min_depth_from_root
           FROM step_depths
          GROUP BY step_depths.workflow_step_id) depth_info ON ((depth_info.workflow_step_id = ws.workflow_step_id)));


--
-- Name: tasker_step_readiness_statuses; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tasker_step_readiness_statuses AS
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
            WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * '00:00:01'::interval)) <= now())
            WHEN (last_failure.created_at IS NOT NULL) THEN ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * '00:00:01'::interval), '00:00:30'::interval)) <= now())
            ELSE true
        END AS retry_eligible,
        CASE
            WHEN (((COALESCE(current_state.to_state, 'pending'::character varying))::text = ANY ((ARRAY['pending'::character varying, 'error'::character varying])::text[])) AND ((dep_edges.to_step_id IS NULL) OR (count(dep_edges.from_step_id) = 0) OR (count(
            CASE
                WHEN ((parent_states.to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) THEN 1
                ELSE NULL::integer
            END) = count(dep_edges.from_step_id))) AND (ws.attempts < COALESCE(ws.retry_limit, 3)) AND (ws.in_process = false) AND (((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL) AND ((ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * '00:00:01'::interval)) <= now())) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NULL)) OR ((ws.backoff_request_seconds IS NULL) AND (last_failure.created_at IS NOT NULL) AND ((last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * '00:00:01'::interval), '00:00:30'::interval)) <= now())))) THEN true
            ELSE false
        END AS ready_for_execution,
    last_failure.created_at AS last_failure_at,
        CASE
            WHEN ((ws.backoff_request_seconds IS NOT NULL) AND (ws.last_attempted_at IS NOT NULL)) THEN (ws.last_attempted_at + ((ws.backoff_request_seconds)::double precision * '00:00:01'::interval))
            WHEN (last_failure.created_at IS NOT NULL) THEN (last_failure.created_at + LEAST((power((2)::double precision, (COALESCE(ws.attempts, 1))::double precision) * '00:00:01'::interval), '00:00:30'::interval))
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
   FROM (((((public.tasker_workflow_steps ws
     JOIN public.tasker_named_steps ns ON ((ns.named_step_id = ws.named_step_id)))
     LEFT JOIN public.tasker_workflow_step_transitions current_state ON (((current_state.workflow_step_id = ws.workflow_step_id) AND (current_state.most_recent = true))))
     LEFT JOIN public.tasker_workflow_step_edges dep_edges ON ((dep_edges.to_step_id = ws.workflow_step_id)))
     LEFT JOIN public.tasker_workflow_step_transitions parent_states ON (((parent_states.workflow_step_id = dep_edges.from_step_id) AND (parent_states.most_recent = true))))
     LEFT JOIN public.tasker_workflow_step_transitions last_failure ON (((last_failure.workflow_step_id = ws.workflow_step_id) AND ((last_failure.to_state)::text = 'error'::text) AND (last_failure.most_recent = true))))
  WHERE ((ws.processed = false) OR (ws.processed IS NULL))
  GROUP BY ws.workflow_step_id, ws.task_id, ws.named_step_id, ns.name, current_state.to_state, last_failure.created_at, ws.attempts, ws.retry_limit, ws.backoff_request_seconds, ws.last_attempted_at, ws.in_process, ws.processed, ws.retryable, dep_edges.to_step_id;


--
-- Name: tasker_task_annotations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasker_task_annotations (
    task_annotation_id bigint NOT NULL,
    task_id bigint NOT NULL,
    annotation_type_id integer NOT NULL,
    annotation jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasker_task_annotations_task_annotation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_task_annotations_task_annotation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_task_annotations_task_annotation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_task_annotations_task_annotation_id_seq OWNED BY public.tasker_task_annotations.task_annotation_id;


--
-- Name: tasker_task_execution_contexts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tasker_task_execution_contexts AS
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
           FROM (public.tasker_workflow_steps ws
             JOIN public.tasker_step_readiness_statuses srs ON ((srs.workflow_step_id = ws.workflow_step_id)))
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
   FROM ((public.tasker_tasks t
     LEFT JOIN public.tasker_task_transitions task_state ON (((task_state.task_id = t.task_id) AND (task_state.most_recent = true))))
     LEFT JOIN step_aggregates ON ((step_aggregates.task_id = t.task_id)));


--
-- Name: tasker_task_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_task_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_task_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_task_transitions_id_seq OWNED BY public.tasker_task_transitions.id;


--
-- Name: tasker_task_workflow_summaries; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tasker_task_workflow_summaries AS
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
   FROM (public.tasker_active_task_execution_contexts atec
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
           FROM public.tasker_active_step_readiness_statuses asrs
          GROUP BY asrs.task_id) workflow_analysis ON ((workflow_analysis.task_id = atec.task_id)));


--
-- Name: tasker_tasks_task_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_tasks_task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_tasks_task_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_tasks_task_id_seq OWNED BY public.tasker_tasks.task_id;


--
-- Name: tasker_workflow_step_edges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_workflow_step_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_workflow_step_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_workflow_step_edges_id_seq OWNED BY public.tasker_workflow_step_edges.id;


--
-- Name: tasker_workflow_step_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_workflow_step_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_workflow_step_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_workflow_step_transitions_id_seq OWNED BY public.tasker_workflow_step_transitions.id;


--
-- Name: tasker_workflow_steps_workflow_step_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasker_workflow_steps_workflow_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasker_workflow_steps_workflow_step_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasker_workflow_steps_workflow_step_id_seq OWNED BY public.tasker_workflow_steps.workflow_step_id;


--
-- Name: tasker_annotation_types annotation_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_annotation_types ALTER COLUMN annotation_type_id SET DEFAULT nextval('public.tasker_annotation_types_annotation_type_id_seq'::regclass);


--
-- Name: tasker_dependent_system_object_maps dependent_system_object_map_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_dependent_system_object_maps ALTER COLUMN dependent_system_object_map_id SET DEFAULT nextval('public.tasker_dependent_system_objec_dependent_system_object_map_i_seq'::regclass);


--
-- Name: tasker_dependent_systems dependent_system_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_dependent_systems ALTER COLUMN dependent_system_id SET DEFAULT nextval('public.tasker_dependent_systems_dependent_system_id_seq'::regclass);


--
-- Name: tasker_named_steps named_step_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_steps ALTER COLUMN named_step_id SET DEFAULT nextval('public.tasker_named_steps_named_step_id_seq'::regclass);


--
-- Name: tasker_named_tasks named_task_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_tasks ALTER COLUMN named_task_id SET DEFAULT nextval('public.tasker_named_tasks_named_task_id_seq'::regclass);


--
-- Name: tasker_named_tasks_named_steps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_tasks_named_steps ALTER COLUMN id SET DEFAULT nextval('public.tasker_named_tasks_named_steps_id_seq'::regclass);


--
-- Name: tasker_task_annotations task_annotation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_annotations ALTER COLUMN task_annotation_id SET DEFAULT nextval('public.tasker_task_annotations_task_annotation_id_seq'::regclass);


--
-- Name: tasker_task_transitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_transitions ALTER COLUMN id SET DEFAULT nextval('public.tasker_task_transitions_id_seq'::regclass);


--
-- Name: tasker_tasks task_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_tasks ALTER COLUMN task_id SET DEFAULT nextval('public.tasker_tasks_task_id_seq'::regclass);


--
-- Name: tasker_workflow_step_edges id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_edges ALTER COLUMN id SET DEFAULT nextval('public.tasker_workflow_step_edges_id_seq'::regclass);


--
-- Name: tasker_workflow_step_transitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_transitions ALTER COLUMN id SET DEFAULT nextval('public.tasker_workflow_step_transitions_id_seq'::regclass);


--
-- Name: tasker_workflow_steps workflow_step_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_steps ALTER COLUMN workflow_step_id SET DEFAULT nextval('public.tasker_workflow_steps_workflow_step_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tasker_annotation_types tasker_annotation_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_annotation_types
    ADD CONSTRAINT tasker_annotation_types_pkey PRIMARY KEY (annotation_type_id);


--
-- Name: tasker_dependent_system_object_maps tasker_dependent_system_object_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_dependent_system_object_maps
    ADD CONSTRAINT tasker_dependent_system_object_maps_pkey PRIMARY KEY (dependent_system_object_map_id);


--
-- Name: tasker_dependent_systems tasker_dependent_systems_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_dependent_systems
    ADD CONSTRAINT tasker_dependent_systems_pkey PRIMARY KEY (dependent_system_id);


--
-- Name: tasker_named_steps tasker_named_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_steps
    ADD CONSTRAINT tasker_named_steps_pkey PRIMARY KEY (named_step_id);


--
-- Name: tasker_named_tasks_named_steps tasker_named_tasks_named_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_tasks_named_steps
    ADD CONSTRAINT tasker_named_tasks_named_steps_pkey PRIMARY KEY (id);


--
-- Name: tasker_named_tasks tasker_named_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_tasks
    ADD CONSTRAINT tasker_named_tasks_pkey PRIMARY KEY (named_task_id);


--
-- Name: tasker_task_annotations tasker_task_annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_annotations
    ADD CONSTRAINT tasker_task_annotations_pkey PRIMARY KEY (task_annotation_id);


--
-- Name: tasker_task_transitions tasker_task_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_transitions
    ADD CONSTRAINT tasker_task_transitions_pkey PRIMARY KEY (id);


--
-- Name: tasker_tasks tasker_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_tasks
    ADD CONSTRAINT tasker_tasks_pkey PRIMARY KEY (task_id);


--
-- Name: tasker_workflow_step_edges tasker_workflow_step_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_edges
    ADD CONSTRAINT tasker_workflow_step_edges_pkey PRIMARY KEY (id);


--
-- Name: tasker_workflow_step_transitions tasker_workflow_step_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_transitions
    ADD CONSTRAINT tasker_workflow_step_transitions_pkey PRIMARY KEY (id);


--
-- Name: tasker_workflow_steps tasker_workflow_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_steps
    ADD CONSTRAINT tasker_workflow_steps_pkey PRIMARY KEY (workflow_step_id);


--
-- Name: annotation_types_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX annotation_types_name_index ON public.tasker_annotation_types USING btree (name);


--
-- Name: annotation_types_name_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX annotation_types_name_unique ON public.tasker_annotation_types USING btree (name);


--
-- Name: dependent_system_object_maps_dependent_system_one_id_dependent_; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dependent_system_object_maps_dependent_system_one_id_dependent_ ON public.tasker_dependent_system_object_maps USING btree (dependent_system_one_id, dependent_system_two_id, remote_id_one, remote_id_two);


--
-- Name: dependent_system_object_maps_dependent_system_one_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dependent_system_object_maps_dependent_system_one_id_index ON public.tasker_dependent_system_object_maps USING btree (dependent_system_one_id);


--
-- Name: dependent_system_object_maps_dependent_system_two_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dependent_system_object_maps_dependent_system_two_id_index ON public.tasker_dependent_system_object_maps USING btree (dependent_system_two_id);


--
-- Name: dependent_system_object_maps_remote_id_one_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dependent_system_object_maps_remote_id_one_index ON public.tasker_dependent_system_object_maps USING btree (remote_id_one);


--
-- Name: dependent_system_object_maps_remote_id_two_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dependent_system_object_maps_remote_id_two_index ON public.tasker_dependent_system_object_maps USING btree (remote_id_two);


--
-- Name: dependent_systems_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dependent_systems_name_index ON public.tasker_dependent_systems USING btree (name);


--
-- Name: dependent_systems_name_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dependent_systems_name_unique ON public.tasker_dependent_systems USING btree (name);


--
-- Name: idx_on_workflow_step_id_most_recent_97d5374ad6; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_workflow_step_id_most_recent_97d5374ad6 ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, most_recent) WHERE (most_recent = true);


--
-- Name: idx_on_workflow_step_id_sort_key_4d476d7adb; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_workflow_step_id_sort_key_4d476d7adb ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, sort_key);


--
-- Name: idx_step_transitions_most_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_step_transitions_most_recent ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, most_recent) WHERE (most_recent = true);


--
-- Name: idx_steps_active_operations; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_steps_active_operations ON public.tasker_workflow_steps USING btree (workflow_step_id, task_id) WHERE ((processed = false) OR (processed IS NULL));


--
-- Name: idx_task_transitions_most_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_transitions_most_recent ON public.tasker_task_transitions USING btree (task_id, most_recent) WHERE (most_recent = true);


--
-- Name: idx_tasks_active_operations; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_active_operations ON public.tasker_tasks USING btree (task_id) WHERE ((complete = false) OR (complete IS NULL));


--
-- Name: idx_tasks_active_workflow_summary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_active_workflow_summary ON public.tasker_tasks USING btree (task_id, complete) WHERE ((complete = false) OR (complete IS NULL));


--
-- Name: idx_tasks_completion_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_completion_status_created ON public.tasker_tasks USING btree (complete, created_at, task_id);


--
-- Name: idx_workflow_step_edges_dependency_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_step_edges_dependency_lookup ON public.tasker_workflow_step_edges USING btree (to_step_id, from_step_id);


--
-- Name: idx_workflow_steps_task_grouping_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_steps_task_grouping_active ON public.tasker_workflow_steps USING btree (task_id, workflow_step_id) WHERE ((processed = false) OR (processed IS NULL));


--
-- Name: index_step_edges_child_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_child_lookup ON public.tasker_workflow_step_edges USING btree (to_step_id);


--
-- Name: index_step_edges_dependency_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_dependency_pair ON public.tasker_workflow_step_edges USING btree (to_step_id, from_step_id);


--
-- Name: index_step_edges_from_step_for_children; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_from_step_for_children ON public.tasker_workflow_step_edges USING btree (from_step_id);


--
-- Name: index_step_edges_from_to_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_from_to_composite ON public.tasker_workflow_step_edges USING btree (from_step_id, to_step_id);


--
-- Name: index_step_edges_parent_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_parent_lookup ON public.tasker_workflow_step_edges USING btree (from_step_id);


--
-- Name: index_step_edges_to_from_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_to_from_composite ON public.tasker_workflow_step_edges USING btree (to_step_id, from_step_id);


--
-- Name: index_step_edges_to_step_for_parents; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_edges_to_step_for_parents ON public.tasker_workflow_step_edges USING btree (to_step_id);


--
-- Name: index_step_transitions_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_transitions_completed ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, to_state) WHERE ((to_state)::text = 'complete'::text);


--
-- Name: index_step_transitions_completed_parents; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_transitions_completed_parents ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, most_recent) WHERE (((to_state)::text = ANY ((ARRAY['complete'::character varying, 'resolved_manually'::character varying])::text[])) AND (most_recent = true));


--
-- Name: index_step_transitions_current_errors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_transitions_current_errors ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, most_recent, created_at) WHERE (((to_state)::text = 'error'::text) AND (most_recent = true));


--
-- Name: index_step_transitions_current_state_optimized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_transitions_current_state_optimized ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, most_recent) WHERE (most_recent = true);


--
-- Name: index_step_transitions_failures_with_timing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_transitions_failures_with_timing ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, to_state, created_at) WHERE ((to_state)::text = 'failed'::text);


--
-- Name: index_step_transitions_for_current_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_transitions_for_current_state ON public.tasker_workflow_step_transitions USING btree (workflow_step_id, created_at);


--
-- Name: index_task_transitions_current_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_transitions_current_state ON public.tasker_task_transitions USING btree (task_id, created_at);


--
-- Name: index_task_transitions_current_state_optimized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_transitions_current_state_optimized ON public.tasker_task_transitions USING btree (task_id, most_recent) WHERE (most_recent = true);


--
-- Name: index_tasker_task_transitions_on_sort_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasker_task_transitions_on_sort_key ON public.tasker_task_transitions USING btree (sort_key);


--
-- Name: index_tasker_task_transitions_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasker_task_transitions_on_task_id ON public.tasker_task_transitions USING btree (task_id);


--
-- Name: index_tasker_task_transitions_on_task_id_and_most_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tasker_task_transitions_on_task_id_and_most_recent ON public.tasker_task_transitions USING btree (task_id, most_recent) WHERE (most_recent = true);


--
-- Name: index_tasker_task_transitions_on_task_id_and_sort_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tasker_task_transitions_on_task_id_and_sort_key ON public.tasker_task_transitions USING btree (task_id, sort_key);


--
-- Name: index_tasker_workflow_step_edges_on_from_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasker_workflow_step_edges_on_from_step_id ON public.tasker_workflow_step_edges USING btree (from_step_id);


--
-- Name: index_tasker_workflow_step_edges_on_to_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasker_workflow_step_edges_on_to_step_id ON public.tasker_workflow_step_edges USING btree (to_step_id);


--
-- Name: index_tasker_workflow_step_transitions_on_sort_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasker_workflow_step_transitions_on_sort_key ON public.tasker_workflow_step_transitions USING btree (sort_key);


--
-- Name: index_tasker_workflow_step_transitions_on_workflow_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasker_workflow_step_transitions_on_workflow_step_id ON public.tasker_workflow_step_transitions USING btree (workflow_step_id);


--
-- Name: index_tasks_on_identity_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tasks_on_identity_hash ON public.tasker_tasks USING btree (identity_hash);


--
-- Name: index_workflow_step_edges_dependency_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_step_edges_dependency_lookup ON public.tasker_workflow_step_edges USING btree (to_step_id, from_step_id);


--
-- Name: index_workflow_steps_backoff_timing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_backoff_timing ON public.tasker_workflow_steps USING btree (last_attempted_at, backoff_request_seconds) WHERE (backoff_request_seconds IS NOT NULL);


--
-- Name: index_workflow_steps_by_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_by_task ON public.tasker_workflow_steps USING btree (task_id);


--
-- Name: index_workflow_steps_processing_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_processing_status ON public.tasker_workflow_steps USING btree (task_id, processed, in_process);


--
-- Name: index_workflow_steps_retry_logic; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_retry_logic ON public.tasker_workflow_steps USING btree (attempts, retry_limit, retryable);


--
-- Name: index_workflow_steps_retry_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_retry_status ON public.tasker_workflow_steps USING btree (attempts, retry_limit);


--
-- Name: index_workflow_steps_task_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_task_and_id ON public.tasker_workflow_steps USING btree (task_id, workflow_step_id);


--
-- Name: index_workflow_steps_task_and_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_task_and_step_id ON public.tasker_workflow_steps USING btree (task_id, workflow_step_id);


--
-- Name: index_workflow_steps_task_and_step_optimized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_task_and_step_optimized ON public.tasker_workflow_steps USING btree (task_id, workflow_step_id);


--
-- Name: index_workflow_steps_task_covering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_task_covering ON public.tasker_workflow_steps USING btree (task_id) INCLUDE (workflow_step_id, processed, in_process, attempts, retry_limit);


--
-- Name: named_step_by_system_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX named_step_by_system_uniq ON public.tasker_named_steps USING btree (dependent_system_id, name);


--
-- Name: named_steps_dependent_system_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX named_steps_dependent_system_id_index ON public.tasker_named_steps USING btree (dependent_system_id);


--
-- Name: named_steps_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX named_steps_name_index ON public.tasker_named_steps USING btree (name);


--
-- Name: named_tasks_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX named_tasks_name_index ON public.tasker_named_tasks USING btree (name);


--
-- Name: named_tasks_name_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX named_tasks_name_unique ON public.tasker_named_tasks USING btree (name);


--
-- Name: named_tasks_named_steps_named_step_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX named_tasks_named_steps_named_step_id_index ON public.tasker_named_tasks_named_steps USING btree (named_step_id);


--
-- Name: named_tasks_named_steps_named_task_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX named_tasks_named_steps_named_task_id_index ON public.tasker_named_tasks_named_steps USING btree (named_task_id);


--
-- Name: named_tasks_steps_ids_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX named_tasks_steps_ids_unique ON public.tasker_named_tasks_named_steps USING btree (named_task_id, named_step_id);


--
-- Name: task_annotations_annotation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_annotations_annotation_idx ON public.tasker_task_annotations USING gin (annotation);


--
-- Name: task_annotations_annotation_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_annotations_annotation_idx1 ON public.tasker_task_annotations USING gin (annotation jsonb_path_ops);


--
-- Name: task_annotations_annotation_type_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_annotations_annotation_type_id_index ON public.tasker_task_annotations USING btree (annotation_type_id);


--
-- Name: task_annotations_task_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_annotations_task_id_index ON public.tasker_task_annotations USING btree (task_id);


--
-- Name: tasks_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_context_idx ON public.tasker_tasks USING gin (context);


--
-- Name: tasks_context_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_context_idx1 ON public.tasker_tasks USING gin (context jsonb_path_ops);


--
-- Name: tasks_identity_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_identity_hash_index ON public.tasker_tasks USING btree (identity_hash);


--
-- Name: tasks_named_task_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_named_task_id_index ON public.tasker_tasks USING btree (named_task_id);


--
-- Name: tasks_requested_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_requested_at_index ON public.tasker_tasks USING btree (requested_at);


--
-- Name: tasks_source_system_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_source_system_index ON public.tasker_tasks USING btree (source_system);


--
-- Name: tasks_tags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_tags_idx ON public.tasker_tasks USING gin (tags);


--
-- Name: tasks_tags_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_tags_idx1 ON public.tasker_tasks USING gin (tags jsonb_path_ops);


--
-- Name: workflow_steps_last_attempted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workflow_steps_last_attempted_at_index ON public.tasker_workflow_steps USING btree (last_attempted_at);


--
-- Name: workflow_steps_named_step_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workflow_steps_named_step_id_index ON public.tasker_workflow_steps USING btree (named_step_id);


--
-- Name: workflow_steps_processed_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workflow_steps_processed_at_index ON public.tasker_workflow_steps USING btree (processed_at);


--
-- Name: workflow_steps_task_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workflow_steps_task_id_index ON public.tasker_workflow_steps USING btree (task_id);


--
-- Name: tasker_dependent_system_object_maps dependent_system_object_maps_dependent_system_one_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_dependent_system_object_maps
    ADD CONSTRAINT dependent_system_object_maps_dependent_system_one_id_foreign FOREIGN KEY (dependent_system_one_id) REFERENCES public.tasker_dependent_systems(dependent_system_id);


--
-- Name: tasker_dependent_system_object_maps dependent_system_object_maps_dependent_system_two_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_dependent_system_object_maps
    ADD CONSTRAINT dependent_system_object_maps_dependent_system_two_id_foreign FOREIGN KEY (dependent_system_two_id) REFERENCES public.tasker_dependent_systems(dependent_system_id);


--
-- Name: tasker_workflow_step_transitions fk_rails_6e0f6eb833; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_transitions
    ADD CONSTRAINT fk_rails_6e0f6eb833 FOREIGN KEY (workflow_step_id) REFERENCES public.tasker_workflow_steps(workflow_step_id);


--
-- Name: tasker_workflow_step_edges fk_rails_7b4652ccf2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_edges
    ADD CONSTRAINT fk_rails_7b4652ccf2 FOREIGN KEY (from_step_id) REFERENCES public.tasker_workflow_steps(workflow_step_id);


--
-- Name: tasker_workflow_step_edges fk_rails_93ec0bf6eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_step_edges
    ADD CONSTRAINT fk_rails_93ec0bf6eb FOREIGN KEY (to_step_id) REFERENCES public.tasker_workflow_steps(workflow_step_id);


--
-- Name: tasker_task_transitions fk_rails_e8caec803c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_transitions
    ADD CONSTRAINT fk_rails_e8caec803c FOREIGN KEY (task_id) REFERENCES public.tasker_tasks(task_id);


--
-- Name: tasker_named_steps named_steps_dependent_system_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_steps
    ADD CONSTRAINT named_steps_dependent_system_id_foreign FOREIGN KEY (dependent_system_id) REFERENCES public.tasker_dependent_systems(dependent_system_id);


--
-- Name: tasker_named_tasks_named_steps named_tasks_named_steps_named_step_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_tasks_named_steps
    ADD CONSTRAINT named_tasks_named_steps_named_step_id_foreign FOREIGN KEY (named_step_id) REFERENCES public.tasker_named_steps(named_step_id);


--
-- Name: tasker_named_tasks_named_steps named_tasks_named_steps_named_task_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_named_tasks_named_steps
    ADD CONSTRAINT named_tasks_named_steps_named_task_id_foreign FOREIGN KEY (named_task_id) REFERENCES public.tasker_named_tasks(named_task_id);


--
-- Name: tasker_task_annotations task_annotations_annotation_type_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_annotations
    ADD CONSTRAINT task_annotations_annotation_type_id_foreign FOREIGN KEY (annotation_type_id) REFERENCES public.tasker_annotation_types(annotation_type_id);


--
-- Name: tasker_task_annotations task_annotations_task_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_task_annotations
    ADD CONSTRAINT task_annotations_task_id_foreign FOREIGN KEY (task_id) REFERENCES public.tasker_tasks(task_id);


--
-- Name: tasker_tasks tasks_named_task_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_tasks
    ADD CONSTRAINT tasks_named_task_id_foreign FOREIGN KEY (named_task_id) REFERENCES public.tasker_named_tasks(named_task_id);


--
-- Name: tasker_workflow_steps workflow_steps_named_step_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_steps
    ADD CONSTRAINT workflow_steps_named_step_id_foreign FOREIGN KEY (named_step_id) REFERENCES public.tasker_named_steps(named_step_id);


--
-- Name: tasker_workflow_steps workflow_steps_task_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasker_workflow_steps
    ADD CONSTRAINT workflow_steps_task_id_foreign FOREIGN KEY (task_id) REFERENCES public.tasker_tasks(task_id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20250612000007'),
('20250612000006'),
('20250612000005'),
('20250612000004'),
('20250612000003'),
('20250612000002'),
('20250612000001'),
('20250611000001'),
('20250604102259'),
('20250604101431'),
('20250603132849'),
('20250603132742'),
('20250603131344'),
('20250528143344'),
('20250525001940'),
('20250524233039'),
('20250413105135'),
('20250331125551'),
('20210826013425');

