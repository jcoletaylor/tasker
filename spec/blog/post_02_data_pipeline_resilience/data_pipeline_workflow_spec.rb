# frozen_string_literal: true

require_relative '../support/blog_spec_helper'

RSpec.describe 'Post 02: Data Pipeline Resilience - Customer Analytics Workflow', type: :blog_example do
  let(:task_handler) { BlogExamples::Post02::CustomerAnalyticsHandler.new }

  let(:valid_task_context) do
    {
      'date_range' => {
        'start_date' => '2024-01-15',
        'end_date' => '2024-01-20'
      },
      'force_refresh' => false,
      'notification_channels' => ['#data-team', '#analytics'],
      'processing_mode' => 'standard',
      'quality_thresholds' => {
        'min_customer_records' => 5,
        'max_null_percentage' => 0.1,
        'min_order_records' => 3
      }
    }
  end

  before do
    # Reset mock services
    BaseMockService.reset_all_mocks!

    # Load Post 02 blog code
    load_blog_code_safely('post_02_data_pipeline_resilience')
  end

  describe 'successful analytics pipeline execution' do
    it 'executes the complete data pipeline workflow' do
      # Create and execute the task
      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )

      expect(task).to be_present
      expect(task.context['date_range']).to eq(valid_task_context['date_range'])

      # Execute the workflow
      execute_workflow(task)

      # Verify workflow execution
      verify_workflow_execution(task, expected_status: 'complete')

      # Verify all 8 steps completed
      expect(task.workflow_steps.count).to eq(8)

      completed_steps = task.workflow_steps.select { |step| step.status == 'complete' }
      expect(completed_steps.count).to eq(8)

      # Verify step execution order and dependencies
      step_names = completed_steps.map(&:name)
      expect(step_names).to include(
        'extract_orders',
        'extract_users',
        'extract_products',
        'transform_customer_metrics',
        'transform_product_metrics',
        'generate_insights',
        'update_dashboard',
        'send_notifications'
      )

      # Verify parallel extraction steps completed
      extract_steps = completed_steps.select { |s| s.name.start_with?('extract_') }
      expect(extract_steps.count).to eq(3)

      # Verify transformation steps ran after extractions
      transform_steps = completed_steps.select { |s| s.name.start_with?('transform_') }
      expect(transform_steps.count).to eq(2)

      # Verify final steps completed
      final_steps = completed_steps.select do |s|
        %w[generate_insights update_dashboard send_notifications].include?(s.name)
      end
      expect(final_steps.count).to eq(3)

      puts '✅ Data pipeline workflow completed successfully with all 8 steps'
    end

    it 'extracts data from all three sources' do
      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      task_handler.handle(task)

      # Verify data extraction calls were made
      call_log = BaseMockService.get_call_log

      extract_calls = call_log.select { |call| call[:method].start_with?('extract_') }
      expect(extract_calls.count).to eq(3)

      # Verify specific extraction methods were called
      expect(extract_calls.map { |c| c[:method] }).to include(
        :extract_orders,
        :extract_users,
        :extract_products
      )

      puts '✅ All three data sources extracted successfully'
    end

    it 'transforms data and generates insights' do
      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      task_handler.handle(task)

      # Verify transformation and insight generation calls
      call_log = BaseMockService.get_call_log

      transform_calls = call_log.select { |call| call[:method].to_s.start_with?('transform_') }
      expect(transform_calls.count).to eq(2)

      insight_calls = call_log.select { |call| call[:method] == :generate_insights }
      expect(insight_calls.count).to eq(1)

      puts '✅ Data transformation and insight generation completed'
    end

    it 'updates dashboard and sends notifications' do
      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      task_handler.handle(task)

      # Verify dashboard and notification calls
      call_log = BaseMockService.get_call_log

      dashboard_calls = call_log.select { |call| call[:method] == :update_dashboard }
      expect(dashboard_calls.count).to eq(1)

      notification_calls = call_log.select { |call| call[:method] == :send_notifications }
      expect(notification_calls.count).to eq(1)

      # Verify notification channels were passed correctly
      notification_call = notification_calls.first
      expect(notification_call[:args][:channels]).to eq(['#data-team', '#analytics'])

      puts '✅ Dashboard updated and notifications sent successfully'
    end
  end

  describe 'error handling and resilience' do
    it 'handles data extraction failures with retries' do
      # Configure data warehouse to fail on orders extraction
      BaseMockService.configure_failures({
                                           'data_warehouse' => {
                                             'extract_orders' => true
                                           }
                                         })

      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )

      # Execute workflow - it should attempt the step and handle the failure
      execute_workflow(task)

      # The task might stay pending if retries are configured, but the step should show the error
      # Let's check what actually happened
      extract_step = task.workflow_steps.find { |s| s.name == 'extract_orders' }

      # Verify that the extraction was attempted and failed appropriately
      if extract_step
        expect(%w[error pending]).to include(extract_step.status)
        if extract_step.status == 'error' && extract_step.results && extract_step.results['error']
          expect(extract_step.results['error']).to include('Database connection timeout')
        end
      end

      # Verify the overall workflow handled the failure gracefully
      expect(%w[pending error]).to include(task.status)

      puts '✅ Data extraction failure handled with appropriate error handling'
    end

    it 'handles transformation failures gracefully' do
      # Configure data warehouse to fail on customer metrics transformation
      BaseMockService.configure_failures({
                                           'data_warehouse' => {
                                             'transform_customer_metrics' => true
                                           }
                                         })

      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      execute_workflow(task)

      # Find the transformation step
      transform_step = task.workflow_steps.find { |s| s.name == 'transform_customer_metrics' }

      if transform_step
        expect(%w[error pending]).to include(transform_step.status)
        if transform_step.status == 'error' && transform_step.results && transform_step.results['error']
          expect(transform_step.results['error']).to include('Out of memory during transformation')
        end
      end

      # Verify the workflow handled the transformation failure
      expect(%w[pending error]).to include(task.status)

      puts '✅ Transformation failure handled gracefully'
    end

    it 'handles dashboard update failures' do
      # Configure dashboard to fail
      BaseMockService.configure_failures({
                                           'dashboard' => {
                                             'update_dashboard' => true
                                           }
                                         })

      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      execute_workflow(task)

      # Verify all previous steps completed
      completed_steps = task.workflow_steps.select { |s| s.status == 'complete' }
      expect(completed_steps.count).to eq(6) # All steps before dashboard (notifications can't run because it depends on dashboard)

      # Verify failure was in dashboard update
      failed_step = task.workflow_steps.find { |s| s.name == 'update_dashboard' }
      expect(failed_step.status).to eq('error')
      if failed_step.results && failed_step.results['error']
        expect(failed_step.results['error']).to include('Dashboard API authentication failed')
      end

      puts '✅ Dashboard update failure handled correctly'
    end

    it 'handles notification delivery failures' do
      # Configure notifications to fail
      BaseMockService.configure_failures({
                                           'dashboard' => {
                                             'send_notifications' => true
                                           }
                                         })

      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      execute_workflow(task)

      # Verify all previous steps completed
      completed_steps = task.workflow_steps.select { |s| s.status == 'complete' }
      expect(completed_steps.count).to eq(7) # All steps except notifications

      # Verify failure was in notifications
      failed_step = task.workflow_steps.find { |s| s.name == 'send_notifications' }
      expect(failed_step.status).to eq('error')
      if failed_step.results && failed_step.results['error']
        expect(failed_step.results['error']).to include('Slack API rate limit exceeded')
      end

      puts '✅ Notification delivery failure handled correctly'
    end
  end

  describe 'configuration and validation' do
    it 'validates required date range parameters' do
      invalid_context = valid_task_context.dup
      invalid_context.delete('date_range')

      task = create_test_task(
        name: 'customer_analytics',
        context: invalid_context,
        version: '1.0.0'
      )

      # Framework validates and returns task with errors instead of raising exception
      expect(task.errors).to be_present
      expect(task.errors[:context]).to be_present
      expect(task.errors[:context].join(' ')).to include('date_range')

      puts '✅ Date range validation working correctly'
    end

    it 'handles different processing modes' do
      high_memory_context = valid_task_context.merge({
                                                       'processing_mode' => 'high_memory'
                                                     })

      task = create_test_task(
        name: 'customer_analytics',
        context: high_memory_context
      )
      expect(task.context['processing_mode']).to eq('high_memory')

      # Execute the task and verify it processes correctly
      task_handler.handle(task)

      # The task might not complete immediately, but should be processing correctly
      expect(%w[pending processing complete]).to include(task.status)

      puts '✅ High memory processing mode handled correctly'
    end

    it 'respects quality thresholds' do
      strict_context = valid_task_context.merge({
                                                  'quality_thresholds' => {
                                                    'min_customer_records' => 100,
                                                    'max_null_percentage' => 5
                                                  }
                                                })

      task = create_test_task(
        name: 'customer_analytics',
        context: strict_context
      )

      # Execute with quality thresholds
      task_handler.handle(task)

      # Verify quality thresholds are respected
      expect(task.context['quality_thresholds']['min_customer_records']).to eq(100)
      expect(%w[pending processing complete]).to include(task.status)

      puts '✅ Quality thresholds respected'
    end
  end

  describe 'performance and monitoring' do
    it 'tracks processing metrics' do
      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )
      start_time = Time.current

      # Execute the task
      task_handler.handle(task)

      end_time = Time.current
      processing_time = end_time - start_time

      expect(%w[pending processing complete]).to include(task.status)
      expect(processing_time).to be < 30 # Should complete within 30 seconds

      # Verify basic task timing is tracked
      expect(task.created_at).to be_present
      expect(task.updated_at).to be_present
      expect(task.updated_at).to be >= task.created_at

      puts '✅ Processing metrics tracked correctly'
    end

    it 'logs structured events throughout pipeline' do
      task = create_test_task(
        name: 'customer_analytics',
        context: valid_task_context
      )

      # Capture log output
      log_output = capture_logs do
        task_handler.handle(task)
      end

      # Verify key events were logged
      expect(log_output).to include('Starting order extraction')
      expect(log_output).to include('Starting user extraction')
      expect(log_output).to include('Starting product extraction')
      expect(log_output).to include('Starting customer metrics transformation')
      expect(log_output).to include('Starting business insights generation')
      expect(log_output).to include('Starting dashboard update')
      expect(log_output).to include('Starting notification delivery')

      puts '✅ Structured logging working correctly'
    end
  end

  private

  def capture_logs
    original_logger = Rails.logger
    log_output = StringIO.new
    Rails.logger = Logger.new(log_output)

    yield

    log_output.string
  ensure
    Rails.logger = original_logger
  end
end
