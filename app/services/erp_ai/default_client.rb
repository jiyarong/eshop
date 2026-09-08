module ErpAI
  class DefaultClient
    class << self
      attr_writer :default_client

      def default_client
        @default_client ||= ActiveAgentClient.new
      end
    end

    def complete(request, &on_stream)
      self.class.default_client.complete(request, &on_stream)
    end
  end
end
