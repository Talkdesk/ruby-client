module SplitIoClient
  module Cache
    module Repositories
      module Impressions
        class RedisRepository < Repository
          IMPRESSIONS_SLICE = 1000

          def initialize(adapter, config)
            @adapter = adapter
            @config = config
          end

          # Store impression data in Redis
          def add(split_name, data)
            @adapter.add_to_set(
              namespace_key("/ruby-#{VERSION}/#{@config.machine_ip}/impressions.#{split_name}"),
              data.merge(split_name: split_name).to_json
            )
          end

          def add_bulk(key, bucketingKey, treatments_labels_changeNumbers, time)
            @adapter.redis.pipelined do
              treatments_labels_changeNumbers.each_slice(IMPRESSIONS_SLICE) do |treatments_labels_changeNumbers_slice|
                treatments_labels_changeNumbers_slice.each do |split_name, treatment_label_changeNumber|
                  add(split_name,
                    'keyName' => key,
                    'bucketingKey' => bucketingKey,
                    'treatment' => treatment_label_changeNumber[:treatment],
                    'label' => @config.labels_enabled ? treatment_label_changeNumber[:label] : nil,
                    'changeNumber' => treatment_label_changeNumber[:changeNumber],
                    'time' => time
                  )
                end
              end
            end
          end

          # Get random impressions from redis in batches of size @config.impressions_queue_size,
          # delete fetched impressions afterwards
          def clear
            impressions = impression_keys.each_with_object([]) do |key, memo|
              _, _, ip, = key.split('/')
              members = @adapter.random_set_elements(key, @config.impressions_queue_size)
              members.each do |impression|
                parsed_impression = JSON.parse(impression)

                memo << {
                  feature: parsed_impression['split_name'],
                  impressions: parsed_impression.reject { |k| k == 'split_name' },
                  ip: ip
                }
              end

              @adapter.delete_from_set(key, members)
            end

            impressions
          end

          private

          # Get all sets by prefix
          def impression_keys
            @adapter.find_sets_by_prefix("#{@config.redis_namespace}/*/impressions.*")
          end
        end
      end
    end
  end
end
