module SplitIoClient
  module Api
    class Splits < Client
      def initialize(api_key, config, metrics)
        @api_key = api_key
        @config = config
        @metrics = metrics
      end

      def since(since)
        start = Time.now
        prefix = 'splitChangeFetcher'
        splits = get_api("#{@config.base_uri}/splitChanges", @config, @api_key, since: since)
        status = splits.status[0].to_i

        if splits == false
          @config.logger.error("Failed to make a http request")
        elsif (200..299).include? status
          result = splits_with_segment_names(splits)

          @metrics.count("#{prefix}.status.#{status}", 1)

          @config.logger.debug("#{result[:splits].length} splits retrieved. since=#{since}") if @config.debug_enabled and result[:splits].length > 0
          @config.logger.debug("#{result}") if @config.transport_debug_enabled
        else
          @metrics.count("#{prefix}.status.#{status}", 1)

          @config.logger.error('Unexpected result from Splits API call')
        end

        latency = (Time.now - start) * 1000.0
        @metrics.time(prefix + '.time', latency)

        result
      end

      private

      def splits_with_segment_names(splits_json)
        parsed_splits = JSON.parse(splits_json, symbolize_names: true)

        parsed_splits[:segment_names] =
          parsed_splits[:splits].each_with_object(Set.new) do |split, splits|
            splits << segment_names(split)
          end.flatten

        parsed_splits
      end

      def segment_names(split)
        split[:conditions].each_with_object(Set.new) do |condition, names|
          condition[:matcherGroup][:matchers].each do |matcher|
            next if matcher[:userDefinedSegmentMatcherData].nil?

            names << matcher[:userDefinedSegmentMatcherData][:segmentName]
          end
        end
      end
    end
  end
end
