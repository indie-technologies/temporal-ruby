require 'temporal/connection/grpc'

module Temporal
  module Connection
    CLIENT_TYPES_MAP = {
      grpc: Temporal::Connection::GRPC
    }.freeze

    def self.generate(configuration)
      connection_class = CLIENT_TYPES_MAP[configuration.type]
      host = configuration.host
      port = configuration.port
      credentials = :this_channel_is_insecure

      unless configuration.credentials.nil?
        credentials = configuration.credentials
      end

      hostname = `hostname`
      thread_id = Thread.current.object_id
      identity = "#{thread_id}@#{hostname}"

      if configuration.type == :grpc
        connection_class.new(host, port, identity, credentials)
      else
        connection_class.new(host, port, identity)
    end
  end
end
