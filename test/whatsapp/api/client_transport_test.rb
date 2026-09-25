# frozen_string_literal: true

require 'test_helper'
require 'api/client'
require 'api/api_configuration'
require 'whatsapp_sdk'
require 'stringio'

module WhatsappSdk
  module Api
    class ClientTransportTest < Minitest::Test
      # Observe what the SDK passes to the transport without opening real sockets.
      class RecordingAdapter < Faraday::Adapter
        class << self
          attr_accessor :requests, :closed
        end

        def call(env)
          super
          self.class.requests << { adapter: self, url: env.url.to_s, headers: env.request_headers.dup,
                                   body: env.body, options: env.request.dup }
          save_response(env, 200, '{"success":true}', {})
          @app.call(env)
        end

        def close
          self.class.closed << self
        end
      end

      def setup
        RecordingAdapter.requests = []
        RecordingAdapter.closed = []
      end

      def test_reuses_transport_per_client_url_and_multipart_mode
        first = Client.new('first-token', 'v25.0', adapter: RecordingAdapter)
        second = Client.new('second-token', 'v25.0', adapter: RecordingAdapter)
        first.send_request(endpoint: 'messages')
        first.send_request(endpoint: 'messages')
        first.send_request(endpoint: 'media', multipart: true)
        first.send_request(endpoint: 'messages', full_url: 'https://graph.facebook.com/v24.0/')
        second.send_request(endpoint: 'messages')

        adapters = RecordingAdapter.requests.map { |r| r[:adapter] }
        assert_same(adapters[0], adapters[1])
        assert_equal(4, adapters.uniq.size)
      end

      def test_request_token_overrides_do_not_leak_to_other_requests_or_clients
        first = Client.new('first-token', 'v25.0', adapter: RecordingAdapter)
        second = Client.new('second-token', 'v25.0', adapter: RecordingAdapter)
        first.send_request(endpoint: 'messages', headers: { 'Authorization' => 'Bearer override' })
        second.send_request(endpoint: 'messages')
        first.send_request(endpoint: 'messages')

        assert_equal(['Bearer override', 'Bearer second-token', 'Bearer first-token'],
                     RecordingAdapter.requests.map { |r| r[:headers]['Authorization'] })
      end

      def test_applies_timeouts_with_multipart_overrides_without_mutating_callers_options
        options = { open_timeout: 5, timeout: 15 }
        client = Client.new('token', 'v25.0', adapter: RecordingAdapter, request_options: options,
                                              multipart_request_options: { timeout: 60 })
        options[:timeout] = 99
        client.send_request(endpoint: 'messages')
        client.send_request(endpoint: 'media', multipart: true)
        normal, multipart = RecordingAdapter.requests.map { |r| r[:options] }

        assert_equal(5, normal.open_timeout)
        assert_equal(15, normal.timeout)
        assert_equal(5, multipart.open_timeout)
        assert_equal(60, multipart.timeout)
      end

      def test_preserves_json_form_multipart_and_logger_with_the_configured_adapter
        output = StringIO.new
        client = Client.new('token', 'v25.0', Logger.new(output), { bodies: false }, adapter: RecordingAdapter)
        client.send_request(endpoint: 'json', params: { text: 'Olá' },
                            headers: { 'Content-Type' => 'application/json' })
        client.send_request(endpoint: 'form', params: { text: 'Olá' })
        File.open('test/fixtures/assets/whatsapp.png', 'rb') do |file|
          client.send_request(endpoint: 'media', params: { file: Faraday::FilePart.new(file, 'image/png') },
                              multipart: true)
        end
        json, form, multipart = RecordingAdapter.requests

        assert_equal('{"text":"Olá"}', json[:body])
        assert_equal('text=Ol%C3%A1', form[:body])
        assert_match(%r{\Amultipart/form-data; boundary=}, multipart[:headers]['Content-Type'])
        assert_respond_to(multipart[:body], :read)
        assert_includes(output.string, '/v25.0/json')
      end

      def test_preserves_keyword_style_logger_options
        output = StringIO.new
        client = Client.new('token', 'v25.0', Logger.new(output), bodies: true, adapter: RecordingAdapter)
        client.send_request(endpoint: 'messages', params: { text: 'logged-message' })

        assert_includes(output.string, 'text=logged-message')
      end

      def test_close_releases_connections_and_allows_new_requests
        client = Client.new('token', 'v25.0', adapter: RecordingAdapter)
        client.send_request(endpoint: 'messages')
        original = RecordingAdapter.requests.first[:adapter]
        client.close
        client.close
        client.send_request(endpoint: 'messages')

        assert_equal([original], RecordingAdapter.closed)
        refute_same(original, RecordingAdapter.requests.last[:adapter])
      end
    end
  end
end
