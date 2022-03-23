require_relative "proxy/communications"
require_relative "activities"

module SynchronousProxy
  RegisterStage = "register".freeze
  SizeStage = "size".freeze
  ColorStage = "color".freeze
  ShippingStage = "shipping".freeze

  TShirtSizes = ["small", "medium", "large"]
  TShirtColors = ["red", "blue", "black"]

  OrderStatus = Struct.new(:order_id, :stage, keyword_init: true)
  TShirtOrder = Struct.new(:email, :size, :color) do
    def to_s
      "size: #{size}, color: #{color}"
    end
  end

  class OrderWorkflow < Temporal::Workflow
    include Proxy::Communications # defines #receive_request, #receive_response, #send_error_response, #send_request, and #send_response

    timeouts start_to_close: 60

    def execute
      order = TShirtOrder.new
      setup_signal_handler

      # Loop until we receive a valid email
      loop do
        signal_detail = receive_request("email_payload")
        source_id, email = signal_detail.calling_workflow_id, signal_detail.value
        future = RegisterEmailActivity.execute(email)

        future.failed do |exception|
          send_error_response(source_id, exception)
          logger.warn "RegisterEmailActivity returned an error, loop back to top"
        end

        future.done do
          order.email = email
          send_response(source_id, SizeStage, "")
        end

        future.get
        break unless future.failed?
      end

      # Loop until we receive a valid size
      loop do
        signal_detail = receive_request("size_payload")
        source_id, size = signal_detail.calling_workflow_id, signal_detail.value
        future = ValidateSizeActivity.execute(size)

        future.failed do |exception|
          send_error_response(source_id, exception)
          logger.warn "ValidateSizeActivity returned an error, loop back to top"
        end

        future.done do
          order.size = size
          logger.info "ValidateSizeActivity succeeded, progress to next stage"
          send_response(source_id, ColorStage, "")
        end

        future.get # block waiting for response
        break unless future.failed?
      end

      # Loop until we receive a valid color
      loop do
        signal_detail = receive_request("color_payload")
        source_id, color = signal_detail.calling_workflow_id, signal_detail.value
        future = ValidateColorActivity.execute(color)

        future.failed do |exception|
          send_error_response(source_id, exception)
          logger.warn "ValidateColorActivity returned an error, loop back to top"
        end

        future.done do
          order.color = color
          logger.info "ValidateColorActivity succeeded, progress to next stage"
          send_response(source_id, ShippingStage, "")
        end

        future.get # block waiting for response
        break unless future.failed?
      end

      # #execute_workflow! blocks until child workflow exits with a result
      workflow.execute_workflow!(SynchronousProxy::ShippingWorkflow, order, workflow.metadata.id)
      nil
    end
  end

  class UpdateOrderWorkflow < Temporal::Workflow
    include Proxy::Communications
    timeouts start_to_close: 60

    def execute(order_workflow_id, stage, value)
      w_id = workflow.metadata.id
      setup_signal_handler
      status = OrderStatus.new(order_id: order_workflow_id, stage: stage)
      signal_workflow_execution_response = send_request(order_workflow_id, stage, value)

      signal_details = receive_response("#{stage}_stage_payload")
      logger.warn "UpdateOrderWorkflow received signal_details #{signal_details.inspect}, error? #{signal_details.error?}"
      raise signal_details.value.class, signal_details.value.message if signal_details.error?

      status.stage = signal_details.key # next stage
      status
    end
  end

  class ShippingWorkflow < Temporal::Workflow
    timeouts run: 60

    def execute(order, order_workflow_id)
      future = ScheduleDeliveryActivity.execute(order_workflow_id)

      future.failed do |exception|
        logger.warn "ShippingWorkflow, ScheduleDelivery failed"
      end

      future.done do |delivery_date|
        SendDeliveryEmailActivity.execute!(order, order_workflow_id, delivery_date)
      end

      future.get
    end
  end
end
