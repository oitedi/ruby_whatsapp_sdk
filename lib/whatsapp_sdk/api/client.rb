# frozen_string_literal: true

require "faraday"
require "faraday/multipart"

module WhatsappSdk
  module Api
    class Client
      API_VERSIONS = [
        'v25.0', 'v24.0', 'v23.0', 'v22.0', 'v21.0', 'v20.0', 'v19.0', 'v18.0', 'v17.0', 'v16.0', 'v15.0', 'v14.0',
        'v13.0', 'v12.0', 'v11.0', 'v10.0', 'v9.0', 'v8.0', 'v7.0', 'v6.0', 'v5.0', 'v4.0',
        'v3.3', 'v3.2', 'v3.1', 'v3.0', 'v2.12', 'v2.11', 'v2.10', 'v2.9', 'v2.8', 'v2.7',
        'v2.6', 'v2.5', 'v2.4', 'v2.3', 'v2.2', 'v2.1'
      ].freeze
      LOGGER_OPTION_KEYS = %i[headers bodies errors log_level formatter].freeze

      # @param access_token [String, nil] Token used by this client.
      # @param api_version [String] Graph API version.
      # @param logger [Logger, nil] Optional Faraday logger.
      # @param logger_options [Hash] Faraday logging options.
      # @param adapter [Symbol, Class, nil] Faraday adapter; nil means Faraday.default_adapter at connection build.
      #   Require optional adapters before constructing the client.
      # @param request_options [Hash] Faraday request options, such as open_timeout and timeout in seconds.
      # @param multipart_request_options [Hash] Overrides applied only to multipart requests.
      # @param legacy_logger_options [Hash] Logger options supplied as keywords. With a logger, every key is passed to
      #   Faraday's logger, so custom formatter options keep working. Without one, only logger keys are accepted.
      # @raise [ArgumentError] If a keyword, request option, or API version is unsupported.
      def initialize(
        access_token = WhatsappSdk.configuration.access_token,
        api_version = WhatsappSdk.configuration.api_version,
        logger = nil,
        logger_options = {},
        adapter: nil,
        request_options: {},
        multipart_request_options: {},
        **legacy_logger_options
      )
        # Ruby 2.x turns a positional logger_options hash into keywords, so with a logger every key is a logger option.
        unknown_options = logger ? [] : legacy_logger_options.keys - LOGGER_OPTION_KEYS
        raise ArgumentError, "Unknown keyword(s): #{unknown_options.join(', ')}" unless unknown_options.empty?

        validate_request_options(request_options)
        validate_request_options(multipart_request_options)

        @access_token = access_token
        @logger = logger
        @logger_options = logger_options.merge(legacy_logger_options)
        @adapter = adapter
        @request_options = request_options.dup.freeze
        @multipart_request_options = multipart_request_options.dup.freeze
        @connections = {}
        @connections_mutex = Mutex.new
        @connections_idle = ConditionVariable.new
        @in_flight = 0
        @closing = false

        validate_api_version(api_version)
        @api_version = api_version
      end

      def media
        @media ||= WhatsappSdk::Api::Medias.new(self)
      end

      def messages
        @messages ||= WhatsappSdk::Api::Messages.new(self)
      end

      def phone_numbers
        @phone_numbers ||= WhatsappSdk::Api::PhoneNumbers.new(self)
      end

      def business_profiles
        @business_profiles ||= WhatsappSdk::Api::BusinessProfile.new(self)
      end

      # Access business account operations using this client's configuration.
      #
      # @return [Api::BusinessAccount] Cached business account API accessor.
      def business_accounts
        @business_accounts ||= WhatsappSdk::Api::BusinessAccount.new(self)
      end

      def templates
        @templates ||= WhatsappSdk::Api::Templates.new(self)
      end

      # @param raw_response [Boolean] Return the Faraday response without JSON parsing or HTTP error raising.
      # @return [Hash, Array, nil, Faraday::Response] Parsed JSON, or the unmodified HTTP response when requested.
      # @raise [Api::Responses::HttpResponseError] For Graph errors in the default parsed mode.
      def send_request(endpoint: "", full_url: nil, http_method: "post", params: {}, headers: {}, multipart: false,
                       raw_response: false)
        url = request_url(full_url || "#{ApiConfiguration::API_URL}/#{@api_version}/", endpoint)

        connection = checkout_connection(url, multipart)
        begin
          response = connection.public_send(http_method, url.to_s, request_params(params, headers), headers)
        ensure
          checkin_connection
        end

        return response if raw_response

        parsed_body = parse_response_body(response.body)

        if response.status > 499 || Api::Responses::GenericErrorResponse.response_error?(response: parsed_body)
          raise Api::Responses::HttpResponseError.new(http_status: response.status, body: parsed_body)
        end

        parsed_body
      end

      def download_file(url:, content_type_header:, file_path: nil)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@access_token}"
        request.content_type = content_type_header
        req_options = { use_ssl: uri.scheme == "https" }

        response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
          http.request(request)
        end

        File.write(file_path, response.body, mode: 'wb') if response.code == "200" && file_path

        response
      end

      # Close cached Faraday connections. Waits for in-flight requests to finish and holds new ones until done.
      # Later requests create fresh connections. Do not call it from inside a request on this client.
      # @return [void]
      # @raise [StandardError] The first adapter error, after all connections have been closed or attempted.
      def close
        error = nil
        @connections_mutex.synchronize do
          @closing = true
          @connections_idle.wait(@connections_mutex) while @in_flight.positive?
          @connections.each_value do |connection|
            connection.close
          rescue StandardError => e
            error ||= e
          end
          @connections.clear
        ensure
          @closing = false
          @connections_idle.broadcast
        end
        raise error if error
      end

      private

      def parse_response_body(body)
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      end

      def request_params(params, headers)
        return params.to_json if params.is_a?(Hash) && headers['Content-Type'] == 'application/json'

        params
      end

      # Same join rules as Faraday::Connection#build_exclusive_url, so endpoints like "./upload:abc" stay relative.
      def request_url(base_url, endpoint)
        base = URI(base_url)
        return base if endpoint.nil? || endpoint.empty?

        base.path += '/' unless base.path.end_with?('/')
        if !endpoint.start_with?('http://', 'https://', '/', './', '../') || endpoint.start_with?('//')
          endpoint = "./#{endpoint}"
        end
        url = base + endpoint
        url.query ||= base.query
        url
      end

      # Connections are cached per origin, so paging URLs and API versions share one pool.
      def checkout_connection(url, multipart)
        @connections_mutex.synchronize do
          @connections_idle.wait(@connections_mutex) while @closing
          origin = "#{url.scheme}://#{url.host}:#{url.port}"
          # Faraday also builds its adapter lazily; initialize it before sharing the connection.
          connection = @connections[[origin, multipart]] ||= build_faraday(origin, multipart).tap(&:app)
          @in_flight += 1
          connection
        end
      end

      def checkin_connection
        @connections_mutex.synchronize do
          @in_flight -= 1
          @connections_idle.broadcast if @in_flight.zero?
        end
      end

      def build_faraday(url, multipart)
        options = multipart ? @request_options.merge(@multipart_request_options) : @request_options
        ::Faraday.new(url, request: options) do |client|
          client.request(:multipart) if multipart
          client.request(:url_encoded)
          client.adapter(@adapter || ::Faraday.default_adapter)
          client.headers['Authorization'] = "Bearer #{@access_token}" unless @access_token.nil?
          client.response(:logger, @logger, @logger_options) unless @logger.nil?
        end
      end

      def validate_request_options(options)
        unknown = options.keys.map(&:to_sym) - ::Faraday::RequestOptions.members
        raise ArgumentError, "Unknown request option(s): #{unknown.join(', ')}" unless unknown.empty?
      end

      def validate_api_version(api_version)
        raise ArgumentError, "Invalid API version: #{api_version}" unless API_VERSIONS.include?(api_version)
      end
    end
  end
end
