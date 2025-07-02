# Demo controller showing how to use the e-commerce workflow
class CheckoutController < ApplicationController
  before_action :authenticate_user!, except: [:demo_page]

  # Demo page showing the checkout flow
  def demo_page
    @products = Product.active.in_stock
    @sample_cart = [
      { product_id: 1, quantity: 2 },
      { product_id: 3, quantity: 1 }
    ]
  end

  # Create a new order using the Tasker workflow
  def create_order
    task_request = Tasker::Types::TaskRequest.new(
      name: 'process_order',
      namespace: 'ecommerce',
      version: '1.0.0',
      context: {
        cart_items: checkout_params[:cart_items],
        payment_info: checkout_params[:payment_info],
        customer_info: checkout_params[:customer_info]
      }
    )

    # Execute the workflow asynchronously
    task_id = Tasker::HandlerFactory.instance.run_task(task_request)
    task = Tasker::Task.find(task_id)

    render json: {
      success: true,
      task_id: task.task_id,
      status: task.status,
      checkout_url: order_status_path(task_id: task.task_id)
    }
  rescue Tasker::ValidationError => e
    render json: {
      success: false,
      error: 'Invalid checkout data',
      details: e.message
    }, status: :unprocessable_entity
  rescue StandardError => e
    render json: {
      success: false,
      error: 'Checkout failed',
      details: e.message
    }, status: :internal_server_error
  end

    # Check the status of an order workflow
  def order_status
    task = Tasker::Task.find(params[:task_id])

    case task.status
    when 'complete'
      order_step = task.get_step_by_name('create_order')
      order_id = order_step.results['order_id']

      render json: {
        status: 'completed',
        order_id: order_id,
        order_number: order_step.results['order_number'],
        total_amount: order_step.results['total_amount'],
        redirect_url: order_path(order_id),
        task_id: task.task_id
      }
    when 'error'
      failed_steps = task.workflow_steps.where("status = 'error'")
      failed_step = failed_steps.first

      render json: {
        status: 'failed',
        failed_step: failed_step&.name,
        failed_steps: failed_steps.map(&:name),
        retry_url: retry_checkout_path(task_id: task.task_id),
        task_id: task.task_id
      }
    when 'processing'
      # Use workflow summary for accurate progress
      summary = task.workflow_summary
      in_progress_steps = task.workflow_steps.where("status = 'processing'")

      render json: {
        status: 'processing',
        current_step: in_progress_steps.first&.name,
        progress: {
          completed: summary[:completed],
          total: summary[:total_steps],
          percentage: summary[:completion_percentage]
        },
        task_id: task.task_id
      }
    else
      render json: {
        status: task.status,
        message: "Order is #{task.status}",
        task_id: task.task_id
      }
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: 'Order not found'
    }, status: :not_found
  end

  # Retry a failed checkout workflow
  def retry_checkout
    task = Tasker::Task.find(params[:task_id])

    if task.status == 'error'
      # Use the Tasker orchestration to retry the task
      task.update!(status: 'pending')
      Tasker::TaskRunnerJob.perform_later(task.task_id)
      
      render json: {
        success: true,
        message: 'Checkout retry initiated',
        status: task.status,
        task_id: task.task_id
      }
    else
      render json: {
        success: false,
        error: "Cannot retry task in #{task.status} status",
        task_id: task.task_id
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: 'Order not found'
    }, status: :not_found
  end

    # Show detailed workflow execution for debugging
  def workflow_details
    task = Tasker::Task.find(params[:task_id])

    steps_detail = task.workflow_steps.map do |step|
      {
        name: step.name,
        status: step.status,
        results: step.results,
        attempts: step.attempts,
        processed_at: step.processed_at,
        inputs: step.inputs
      }
    end

    # Get comprehensive workflow summary
    summary = task.workflow_summary

    render json: {
      task_id: task.task_id,
      status: task.status,
      workflow_summary: summary,
      steps: steps_detail,
      annotations: task.annotations
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: 'Order not found'
    }, status: :not_found
  end

  private

  def checkout_params
    params.require(:checkout).permit(
      cart_items: [:product_id, :quantity, :price],
      payment_info: [:token, :amount, :payment_method],
      customer_info: [:email, :name, :phone]
    )
  end
end
