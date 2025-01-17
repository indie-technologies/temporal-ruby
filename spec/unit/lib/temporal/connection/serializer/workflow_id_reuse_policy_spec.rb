require 'temporal/retry_policy'
require 'temporal/connection/serializer/retry_policy'

describe Temporal::Connection::Serializer::WorkflowIdReusePolicy do
  describe 'to_proto' do
    SYM_TO_PROTO = {
      allow_failed: Temporal::Api::Enums::V1::WorkflowIdReusePolicy::WORKFLOW_ID_REUSE_POLICY_ALLOW_DUPLICATE_FAILED_ONLY,
      allow: Temporal::Api::Enums::V1::WorkflowIdReusePolicy::WORKFLOW_ID_REUSE_POLICY_ALLOW_DUPLICATE,
      reject: Temporal::Api::Enums::V1::WorkflowIdReusePolicy::WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE
    }.freeze

    def self.test_valid_policy(policy_sym)
      it "serializes #{policy_sym}" do
        proto_enum = described_class.new(policy_sym).to_proto
        expected = SYM_TO_PROTO[policy_sym]
        expect(proto_enum).to eq(expected)
      end
    end

    test_valid_policy(:allow)
    test_valid_policy(:allow_failed)
    test_valid_policy(:reject)

    it "rejects invalid policies" do
      expect do
        described_class.new(:not_a_valid_policy).to_proto
      end.to raise_error(Temporal::Connection::ArgumentError, 'Unknown workflow_id_reuse_policy specified: not_a_valid_policy')
    end
  end
end
