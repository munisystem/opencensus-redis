module OpenCensus
  module Redis

    NAME = 'Redis'.freeze
    LOCALHOST = 'localhost'.freeze
    UNKNOWN = 'unknown'.freeze

    module_function

    def http_host(client)
      client.path ? LOCALHOST : client.host
    rescue StandardError
      UNKNOWN
    end

    def load!
      @done ||= false
      return if @done

      begin
        require 'opencensus'
        require 'redis'

        patch_redis
      rescue StandardError => e
        warn "[opencensus-redis] Failed to apply Redis instrumentation: #{e}"
      ensure
        @done = true
      end
    end

    # rubocop:disable Metrics/MethodLength
    def patch_redis
      require 'redis'

      ::Redis::Client.class_eval do
        alias_method :call_without_opencensus, :call
        def call(*args, &block)
          span_context = ::OpenCensus::Trace.span_context
          return call_without_opencensus(*args, &block) unless span_context

          operation = args[0][0]
          span_name = OpenCensus::Redis::NAME + ' ' + operation.to_s
          span = span_context.start_span(span_name)
          span.put_attribute 'http.host', OpenCensus::Redis.http_host(self)
          begin
            call_without_opencensus(*args, &block)
          ensure
            span_context.end_span(span)
          end
        end

        alias_method :call_pipeline_without_opencensus, :call_pipeline
        def call_pipeline(*args, &block)
          span_context = ::OpenCensus::Trace.span_context
          return call_pipeline_without_opencensus(*args, &block) unless span_context

          pipeline = args[0]
          operation = pipeline.is_a?(::Redis::Pipeline::Multi) ? 'multi' : 'pipeline'
          span_name = OpenCensus::Redis::NAME + ' ' + operation.to_s
          span = span_context.start_span(span_name)
          span.put_attribute 'http.host', OpenCensus::Redis.http_host(self)
          begin
            call_pipeline_without_opencensus(*args, &block)
          ensure
            span_context.end_span(span)
          end
        end
      end
    end
    # rubocop:enable Metrics/MethodLength

    private_class_method :patch_redis
  end
end

OpenCensus::Redis.load!
