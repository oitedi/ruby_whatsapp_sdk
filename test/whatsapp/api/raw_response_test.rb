# frozen_string_literal: true

require 'test_helper'
require 'api/client'
require 'whatsapp_sdk'

module WhatsappSdk
  module Api
    class RawResponseTest < Minitest::Test
      def setup
        @client = Client.new('store-token', 'v24.0')
      end

      def test_raw_response_preserves_status_headers_and_body_even_for_non_json_errors
        cases = [[200, '{"messages":[{"id":"wamid"}]}'], [204, ''], [403, '{}'], [429, ''],
                 [502, '<html>Bad gateway</html>']]
        cases.each do |status, body|
          request = stub_request(:post, 'https://graph.facebook.com/v24.0/sender/messages')
                    .with(headers: { 'Authorization' => 'Bearer store-token' })
                    .to_return(status: status, body: body, headers: { 'Retry-After' => '30' })

          response = @client.send_request(endpoint: 'sender/messages', raw_response: true)

          assert_instance_of(Faraday::Response, response)
          assert_equal(status, response.status)
          assert_equal(body, response.body)
          assert_equal('30', response.headers['retry-after'])
          assert_requested(request, times: 1)
          WebMock.reset!
        end
      end

      def test_default_mode_still_parses_json_and_raises_graph_errors
        stub_request(:post, 'https://graph.facebook.com/v24.0/sender/messages')
          .to_return(status: 200, body: '{"success":true}')
          .then.to_return(status: 400, body: '{"error":{"message":"Invalid recipient","code":100}}')

        assert_equal({ 'success' => true }, @client.send_request(endpoint: 'sender/messages'))
        error = assert_raises(Responses::HttpResponseError) { @client.send_request(endpoint: 'sender/messages') }
        assert_equal(400, error.http_status)
      end
    end
  end
end
