# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'State Machine Debug Investigation', type: :model do
  describe 'investigating empty string state issue' do
    before do
      # Clean up any existing data in proper foreign key order
      puts "\n=== CLEANING UP EXISTING DATA ==="

      # Check what exists before cleanup
      task_transitions = Tasker::TaskTransition.count
      step_transitions = Tasker::WorkflowStepTransition.count
      step_edges = Tasker::WorkflowStepEdge.count
      steps = Tasker::WorkflowStep.count
      tasks = Tasker::Task.count

      puts "Before cleanup: #{task_transitions} task transitions, #{step_transitions} step transitions, #{step_edges} edges, #{steps} steps, #{tasks} tasks"

      # Check for problematic transitions BEFORE cleanup
      problematic_before = Tasker::WorkflowStepTransition.where(
        "from_state = '' OR to_state = ''"
      )
      puts "Found #{problematic_before.count} problematic transitions BEFORE cleanup:"
      problematic_before.each do |t|
        puts "  EXISTING PROBLEM: step_id=#{t.workflow_step_id}, from='#{t.from_state}', to='#{t.to_state}', most_recent=#{t.most_recent}, created_at=#{t.created_at}"
      end

      # Clean up in proper order to avoid foreign key violations
      Tasker::WorkflowStepTransition.delete_all
      Tasker::TaskTransition.delete_all
      Tasker::WorkflowStepEdge.delete_all
      Tasker::WorkflowStep.delete_all
      Tasker::Task.delete_all

      puts "After cleanup: All data removed"
    end

    it 'investigates the transition lifecycle BEFORE guard clause' do
      puts "\n=== TRANSITION LIFECYCLE DEBUG (PRE-GUARD) ==="

      # Create a task using the factory that's failing
      task = create(:linear_workflow_task)
      puts "Created task: #{task.task_id}"

      # Get the first step
      step = task.workflow_steps.first
      puts "Step ID: #{step.workflow_step_id}"
      puts "Step name: #{step.name}"

      # Check what's in the database for transitions
      puts "\n=== DATABASE STATE INVESTIGATION ==="
      all_transitions = Tasker::WorkflowStepTransition.where(workflow_step_id: step.workflow_step_id)
      puts "Total transitions in DB: #{all_transitions.count}"

      all_transitions.each_with_index do |t, idx|
        puts "  #{idx}: ID=#{t.id}, from='#{t.from_state}' (#{t.from_state.class}), to='#{t.to_state}' (#{t.to_state.class}), most_recent=#{t.most_recent}, sort_key=#{t.sort_key}"
        puts "       from_state.blank?=#{t.from_state.blank?}, to_state.blank?=#{t.to_state.blank?}"
      end

      # Check most_recent specifically
      most_recent_transitions = all_transitions.where(most_recent: true)
      puts "\nMost recent transitions: #{most_recent_transitions.count}"
      most_recent_transitions.each do |t|
        puts "  Most recent: from='#{t.from_state}' to='#{t.to_state}'"
      end

      # Test our custom current_state implementation
      puts "\n=== CUSTOM CURRENT_STATE INVESTIGATION ==="
      state_machine = step.state_machine

      # Check the most_recent_transition query directly
      most_recent_transition = step.workflow_step_transitions.where(most_recent: true).first
      puts "Direct most_recent query result: #{most_recent_transition.inspect}"

      if most_recent_transition
        puts "Most recent transition details:"
        puts "  from_state: '#{most_recent_transition.from_state}' (#{most_recent_transition.from_state.class})"
        puts "  to_state: '#{most_recent_transition.to_state}' (#{most_recent_transition.to_state.class})"
        puts "  from_state.blank?: #{most_recent_transition.from_state.blank?}"
        puts "  to_state.blank?: #{most_recent_transition.to_state.blank?}"
      end

      # Test current_state method
      current_state_result = state_machine.current_state
      puts "current_state() returns: '#{current_state_result}' (#{current_state_result.class})"
      puts "current_state.blank?: #{current_state_result.blank?}"

      # Now let's intercept what Statesman does when building transitions
      puts "\n=== STATESMAN TRANSITION BUILDING DEBUG ==="

      # Let's manually try to build what Statesman would build
      # by calling the private methods if we can access them
      begin
        # Check if we can access Statesman's transition building
        puts "State machine metadata:"
        puts "  transition_class: #{state_machine.transition_class}"
        puts "  association_name: #{state_machine.association_name}"

        # Try to see what Statesman would use as the from_state
        puts "\nStatesman's view of current state:"

        # The issue might be in how Statesman determines the from_state
        # Let's check if there are any blank/empty states in the database
        puts "\nChecking for problematic states in database:"
        problematic_transitions = Tasker::WorkflowStepTransition.where(
          "from_state = '' OR to_state = '' OR from_state IS NULL OR to_state IS NULL"
        )
        puts "Found #{problematic_transitions.count} problematic transitions"
        problematic_transitions.each do |t|
          puts "  Problem transition: step_id=#{t.workflow_step_id}, from='#{t.from_state}', to='#{t.to_state}', most_recent=#{t.most_recent}"
        end

      rescue => e
        puts "Error accessing Statesman internals: #{e.message}"
      end

      # Let's try to trigger the exact same transition that's failing
      puts "\n=== ATTEMPTING FAILING TRANSITION WITH DEBUG ==="

      # Override the guard method temporarily to see what it receives
      original_guard_method = nil
      begin
        # Get the state machine class
        sm_class = state_machine.class

        # Store the original guard_failed_callback if it exists
        puts "Attempting to intercept guard clause parameters..."

        # Try the transition and catch the specific error
        state_machine.transition_to!(:in_progress)
        puts "Transition succeeded unexpectedly!"

      rescue Statesman::GuardFailedError => e
        puts "CAUGHT GUARD FAILURE!"
        puts "Error message: #{e.message}"

        # Parse the error message to extract the from_state
        if e.message =~ /Guard on transition from: '(.*)' to/
          extracted_from_state = $1
          puts "Extracted from_state from error: '#{extracted_from_state}' (length: #{extracted_from_state.length})"
          puts "Is empty string?: #{extracted_from_state == ''}"
          puts "Is blank?: #{extracted_from_state.blank?}"
        end

      rescue => e
        puts "Other error during transition: #{e.class} - #{e.message}"
      end
    end

    it 'reproduces the exact health count test scenario' do
      puts "\n=== REPRODUCING HEALTH COUNT TEST SCENARIO ==="

      # Do exactly what the health count test does
      puts "1. Creating linear workflow task..."
      task = create(:linear_workflow_task)
      puts "Task created: #{task.task_id}"

      puts "2. Transitioning task to in_progress..."
      task.state_machine.transition_to!(:in_progress)

      puts "3. Getting first step..."
      step = task.workflow_steps.first
      puts "Step: #{step.workflow_step_id} (#{step.name})"

      # Check database state before set_step_to_error
      puts "\n4. Database state before set_step_to_error..."
      transitions_before = step.workflow_step_transitions.count
      puts "Transitions before: #{transitions_before}"

      step.workflow_step_transitions.each do |t|
        puts "  Before: from='#{t.from_state}' to='#{t.to_state}' most_recent=#{t.most_recent}"
      end

      # Check what's in the database GLOBALLY
      puts "\n5. Checking ALL transitions in database..."
      all_problematic = Tasker::WorkflowStepTransition.where(
        "from_state = '' OR to_state = ''"
      )
      puts "Found #{all_problematic.count} problematic transitions globally"
      all_problematic.each do |t|
        puts "  GLOBAL PROBLEM: step_id=#{t.workflow_step_id}, from='#{t.from_state}', to='#{t.to_state}'"
      end

      puts "\n6. About to call set_step_to_error..."
      # Include the factory workflow helpers to use set_step_to_error
      extend FactoryWorkflowHelpers

      begin
        set_step_to_error(step)
        puts "set_step_to_error completed successfully"
      rescue => e
        puts "ERROR IN set_step_to_error: #{e.class} - #{e.message}"
        puts "Backtrace: #{e.backtrace[0..3].join("\n")}"
      end

      # Check database state after set_step_to_error
      puts "\n7. Database state after set_step_to_error..."
      transitions_after = step.workflow_step_transitions.count
      puts "Transitions after: #{transitions_after}"

      step.workflow_step_transitions.order(:sort_key).each do |t|
        puts "  After: from='#{t.from_state}' to='#{t.to_state}' most_recent=#{t.most_recent} sort_key=#{t.sort_key}"
      end

      # Check for empty string states after set_step_to_error
      puts "\n8. Checking for empty string states after set_step_to_error..."
      all_problematic_after = Tasker::WorkflowStepTransition.where(
        "from_state = '' OR to_state = ''"
      )
      puts "Found #{all_problematic_after.count} problematic transitions after set_step_to_error"
      all_problematic_after.each do |t|
        puts "  POST-ERROR PROBLEM: step_id=#{t.workflow_step_id}, from='#{t.from_state}', to='#{t.to_state}', most_recent=#{t.most_recent}"
      end

      # Now try the transition that should fail
      puts "\n9. Testing transition to in_progress (should fail in health count test)..."
      begin
        step.state_machine.transition_to!(:in_progress)
        puts "Transition succeeded (unexpected)"
      rescue Statesman::GuardFailedError => e
        puts "GUARD FAILURE REPRODUCED!"
        puts "Error: #{e.message}"

        # Let's see what Statesman thinks the current state is
        current_state = step.state_machine.current_state
        puts "Current state according to state machine: '#{current_state}'"

        # Check the most recent transition
        most_recent = step.workflow_step_transitions.where(most_recent: true).first
        if most_recent
          puts "Most recent transition in DB: from='#{most_recent.from_state}' to='#{most_recent.to_state}'"
        end
      rescue => e
        puts "Other error: #{e.class} - #{e.message}"
      end
    end

    it 'demonstrates state leakage between tests' do
      puts "\n=== DEMONSTRATING STATE LEAKAGE ==="

      # This test should run AFTER the previous one to show leakage
      puts "1. Checking for existing problematic transitions at start of test..."
      existing_problematic = Tasker::WorkflowStepTransition.where(
        "from_state = '' OR to_state = ''"
      )
      puts "Found #{existing_problematic.count} existing problematic transitions"
      existing_problematic.each do |t|
        puts "  LEAKED: step_id=#{t.workflow_step_id}, from='#{t.from_state}', to='#{t.to_state}', created_at=#{t.created_at}"
      end

      if existing_problematic.any?
        puts "\n*** STATE LEAKAGE CONFIRMED ***"
        puts "Previous test left #{existing_problematic.count} problematic transitions in the database!"
      else
        puts "No state leakage detected (good!)"
      end

      # Check total transitions
      total_transitions = Tasker::WorkflowStepTransition.count
      puts "Total transitions in database: #{total_transitions}"

      if total_transitions > 0
        puts "Transitions found (should be 0 if cleanup worked):"
        Tasker::WorkflowStepTransition.limit(10).each do |t|
          puts "  step_id=#{t.workflow_step_id}, from='#{t.from_state}', to='#{t.to_state}'"
        end
      end
    end
  end
end
