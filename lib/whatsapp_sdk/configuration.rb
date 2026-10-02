# frozen_string_literal: true

module WhatsappSdk
  # This module allows client instantiating the client as a singleton like the following example:
  # WhatsappSdk.configure do |config|
  #   config.access_token = ACCESS_TOKEN
  #   config.api_version = API_VERSION
  # end
  #
  # The gem have access to the client through WhatsappSdk.configuration.client
  class Configuration
    SETTINGS = %i[access_token api_version logger logger_options adapter request_options
                  multipart_request_options].freeze

    # loggers like ActiveSupport::Logger (Rails.logger) is a subclass of Logger
    attr_reader(*SETTINGS)

    # Changing a setting makes #client build a new client on its next call.
    SETTINGS.each do |name|
      define_method(:"#{name}=") do |value|
        @client = nil
        instance_variable_set(:"@#{name}", value)
      end
    end

    def initialize(
      access_token = "",
      api_version = Api::ApiConfiguration::DEFAULT_API_VERSION,
      logger = nil,
      logger_options = {}
    )
      @access_token = access_token
      @api_version = api_version
      @logger = logger
      @logger_options = logger_options
      @adapter = nil
      @request_options = {}
      @multipart_request_options = {}
    end

    # One client is shared by every API object built from this configuration, so its connections are reused.
    # @return [Api::Client]
    def client
      @client ||= Api::Client.new(
        access_token, api_version, logger, logger_options,
        adapter: adapter, request_options: request_options, multipart_request_options: multipart_request_options
      )
    end
  end
end
