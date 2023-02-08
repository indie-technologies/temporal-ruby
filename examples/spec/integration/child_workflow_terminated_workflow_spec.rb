require 'workflows/child_workflow_terminated_workflow.rb'

describe ChildWorkflowTerminatedWorkflow do
  subject { described_class }

  it 'successfully can catch if a child workflow times out' do
    workflow_id = SecureRandom.uuid

    Temporal.start_workflow(
      subject,
      options: { workflow_id: workflow_id }
    )

    result = Temporal.await_workflow_result(
      subject,
      workflow_id: workflow_id
    )

    expect(result[:child_workflow_terminated]).to eq(true)
    expect(result[:error]).to be_a(Temporal::ChildWorkflowTerminatedError)
  end
end
