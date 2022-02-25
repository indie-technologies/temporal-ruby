describe Temporal::Connection::GRPC do
  subject { Temporal::Connection::GRPC.new(nil, nil, nil) }
  let(:grpc_stub) { double('grpc stub') }
  let(:namespace) { 'test-namespace' }
  let(:workflow_id) { SecureRandom.uuid }
  let(:run_id) { SecureRandom.uuid }
  let(:now) { Time.now.utc }
  let(:already_started_error) do
    detail_error = Google::Protobuf::Any.new.tap do |any|
      any.pack(Temporal::Api::ErrorDetails::V1::WorkflowExecutionAlreadyStartedFailure.new(start_request_id: SecureRandom.uuid, run_id: run_id))
    end
    rpc_status = Google::Rpc::Status.new(
      code: 6,
      message: 'Workflow execution already finished successfully. WorkflowId: TestWorkflow-1, RunId: baaf1d86-4459-4ecd-a288-47aeae55245d. Workflow Id reuse policy: allow duplicate workflow Id if last run failed.',
      details: [detail_error],
    )
    GRPC::AlreadyExists.new('details', { 'grpc-status-details-bin' => Google::Rpc::Status.encode(rpc_status) })
  end

  before do
    allow(subject).to receive(:client).and_return(grpc_stub)

    allow(Time).to receive(:now).and_return(now)
  end

  describe '#start_workflow_execution' do
    it 'provides the existing run_id when the workflow is already started' do
      allow(grpc_stub).to receive(:start_workflow_execution).and_raise(already_started_error)

      expect do
        subject.start_workflow_execution(
          namespace: namespace,
          workflow_id: workflow_id,
          workflow_name: 'Test',
          task_queue: 'test',
          execution_timeout: 0,
          run_timeout: 0,
          task_timeout: 0,
          memo: {}
        )
      end.to raise_error(Temporal::WorkflowExecutionAlreadyStartedFailure) do |e|
        expect(e.run_id).to eql(run_id)
      end
    end
  end

  describe '#signal_with_start_workflow' do
    let(:temporal_response) do
      Temporal::Api::WorkflowService::V1::SignalWithStartWorkflowExecutionResponse.new(run_id: 'xxx')
    end

    it 'starts a workflow with a signal with scalar arguments' do
      allow(grpc_stub).to receive(:signal_with_start_workflow_execution).and_return(temporal_response)
      subject.signal_with_start_workflow_execution(
        namespace: namespace,
        workflow_id: workflow_id,
        workflow_name: 'workflow_name',
        task_queue: 'task_queue',
        input: ['foo'],
        execution_timeout: 1,
        run_timeout: 2,
        task_timeout: 3,
        signal_name: 'the question',
        signal_input: 'what do you get if you multiply six by nine?'
      )

      expect(grpc_stub).to have_received(:signal_with_start_workflow_execution) do |request|
        expect(request).to be_an_instance_of(Temporal::Api::WorkflowService::V1::SignalWithStartWorkflowExecutionRequest)
        expect(request.namespace).to eq(namespace)
        expect(request.workflow_id).to eq(workflow_id)
        expect(request.workflow_type.name).to eq('workflow_name')
        expect(request.task_queue.name).to eq('task_queue')
        expect(request.input.payloads[0].data).to eq('"foo"')
        expect(request.workflow_execution_timeout.seconds).to eq(1)
        expect(request.workflow_run_timeout.seconds).to eq(2)
        expect(request.workflow_task_timeout.seconds).to eq(3)
        expect(request.signal_name).to eq('the question')
        expect(request.signal_input.payloads[0].data).to eq('"what do you get if you multiply six by nine?"')
      end
    end

    it 'provides the existing run_id when the workflow is already started' do
      allow(grpc_stub).to receive(:signal_with_start_workflow_execution).and_raise(already_started_error)

      expect do
        subject.signal_with_start_workflow_execution(
          namespace: namespace,
          workflow_id: workflow_id,
          workflow_name: 'workflow_name',
          task_queue: 'task_queue',
          input: ['foo'],
          execution_timeout: 1,
          run_timeout: 2,
          task_timeout: 3,
          signal_name: 'the question',
          signal_input: 'what do you get if you multiply six by nine?',
        )
      end.to raise_error(Temporal::WorkflowExecutionAlreadyStartedFailure) do |e|
        expect(e.run_id).to eql(run_id)
      end
    end
  end

  describe "#list_namespaces" do
    let (:response) do
      Temporal::Api::WorkflowService::V1::ListNamespacesResponse.new(
        namespaces: [Temporal::Api::WorkflowService::V1::DescribeNamespaceResponse.new],
        next_page_token: ""
      )
    end

    before { allow(grpc_stub).to receive(:list_namespaces).and_return(response) }

    it 'calls GRPC service with supplied arguments' do
      next_page_token = "next-page-token-id"

      subject.list_namespaces(
        page_size: 10,
        next_page_token: next_page_token,
      )

      expect(grpc_stub).to have_received(:list_namespaces) do |request|
        expect(request).to be_an_instance_of(Temporal::Api::WorkflowService::V1::ListNamespacesRequest)
        expect(request.page_size).to eq(10)
        expect(request.next_page_token).to eq(next_page_token)
      end
    end
  end

  describe '#get_workflow_execution_history' do
    let(:response) do
      Temporal::Api::WorkflowService::V1::GetWorkflowExecutionHistoryResponse.new(
        history: Temporal::Api::History::V1::History.new,
        next_page_token: nil
      )
    end

    before { allow(grpc_stub).to receive(:get_workflow_execution_history).and_return(response) }

    it 'calls GRPC service with supplied arguments' do
      subject.get_workflow_execution_history(
        namespace: namespace,
        workflow_id: workflow_id,
        run_id: run_id
      )

      expect(grpc_stub).to have_received(:get_workflow_execution_history) do |request|
        expect(request).to be_an_instance_of(Temporal::Api::WorkflowService::V1::GetWorkflowExecutionHistoryRequest)
        expect(request.namespace).to eq(namespace)
        expect(request.execution.workflow_id).to eq(workflow_id)
        expect(request.execution.run_id).to eq(run_id)
        expect(request.next_page_token).to be_empty
        expect(request.wait_new_event).to eq(false)
        expect(request.history_event_filter_type).to eq(
          Temporal::Api::Enums::V1::HistoryEventFilterType.lookup(
            Temporal::Api::Enums::V1::HistoryEventFilterType::HISTORY_EVENT_FILTER_TYPE_ALL_EVENT
          )
        )
      end
    end

    context 'when wait_for_new_event is true' do
      let (:timeout) { 13 }
      it 'calls GRPC service with a deadline' do
        subject.get_workflow_execution_history(
          namespace: namespace,
          workflow_id: workflow_id,
          run_id: run_id,
          wait_for_new_event: true,
          timeout: timeout
        )

        expect(grpc_stub).to have_received(:get_workflow_execution_history) do |request, deadline:|
          expect(request.wait_new_event).to eq(true)
          expect(deadline).to eq(now + timeout)
        end
      end

      it 'demands a timeout to be specified' do
        expect do
          subject.get_workflow_execution_history(
            namespace: namespace,
            workflow_id: workflow_id,
            run_id: run_id,
            wait_for_new_event: true
          )
        end.to raise_error do |e|
          expect(e.message).to eq("You must specify a timeout when wait_for_new_event = true.")
        end
      end

      it 'disallows a timeout larger than the server timeout' do
        expect do
          subject.get_workflow_execution_history(
            namespace: namespace,
            workflow_id: workflow_id,
            run_id: run_id,
            wait_for_new_event: true,
            timeout: 60
          )
        end.to raise_error(Temporal::ClientError) do |e|
          expect(e.message).to eq("You may not specify a timeout of more than 30 seconds, got: 60.")
        end
      end
    end

    context 'when event_type is :close' do
      it 'calls GRPC service' do
        subject.get_workflow_execution_history(
          namespace: namespace,
          workflow_id: workflow_id,
          run_id: run_id,
          event_type: :close
        )

        expect(grpc_stub).to have_received(:get_workflow_execution_history) do |request|
          expect(request.history_event_filter_type).to eq(
            Temporal::Api::Enums::V1::HistoryEventFilterType.lookup(
              Temporal::Api::Enums::V1::HistoryEventFilterType::HISTORY_EVENT_FILTER_TYPE_CLOSE_EVENT
            )
          )
        end
      end
    end
  end
end
