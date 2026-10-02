# frozen_string_literal: true

require 'test_helper'
require 'whatsapp_sdk'

module WhatsappSdk
  module Api
    class FlowAssetsTest < Minitest::Test
      def test_raw_key_configuration_keeps_the_full_http_response
        request = stub_request(:post, 'https://graph.facebook.com/v24.0/phone/whatsapp_business_encryption')
                  .to_return(status: 202, body: '{"success":true,"extra":"preserved"}')
                  .then.to_return(status: 403, body: '<html>Forbidden</html>')

        response = @client.phone_numbers.set_public_key(phone_number_id: 'phone', business_public_key: 'key',
                                                        raw_response: true)
        assert_equal(202, response.status)
        assert_equal('{"success":true,"extra":"preserved"}', response.body)
        response = @client.phone_numbers.set_public_key(phone_number_id: 'phone', business_public_key: 'key',
                                                        raw_response: true)
        assert_equal(403, response.status)
        assert_equal('<html>Forbidden</html>', response.body)
        assert_requested(request, times: 2)
      end

      def test_asset_listing_preserves_http_errors_without_graph_errors
        [[403, '{}'], [429, '']].each do |status, body|
          request = stub_request(:get, 'https://graph.facebook.com/v24.0/flow/assets?limit=100')
                    .to_return(status: status, body: body)
          error = assert_raises(Responses::HttpResponseError) { @client.flows.assets(flow_id: 'flow') }
          assert_equal(status, error.http_status)
          assert_requested(request, times: 1)
          WebMock.reset!
        end
      end

      def setup
        @client = Client.new('flow-token', 'v24.0')
      end

      def test_lists_assets_with_cursors_without_downloading_or_exposing_credentials_to_the_cdn
        asset = { 'name' => 'flow.json', 'asset_type' => 'FLOW_JSON', 'download_url' => 'https://cdn.example.com/flow.json' }
        request = stub_request(:get, 'https://graph.facebook.com/v24.0/flow/assets')
                  .with(query: { limit: '20', after: 'next+/=' }, headers: { 'Authorization' => 'Bearer flow-token' })
                  .to_return(body: { data: [asset], paging: { cursors: { before: 'before', after: 'after' } } }.to_json)

        page = @client.flows.assets(flow_id: 'flow', limit: 20, after: 'next+/=')

        assert_equal([asset], page.records)
        assert_equal('before', page.before)
        assert_equal('after', page.after)
        assert_requested(request, times: 1)
        assert_not_requested(:get, 'https://cdn.example.com/flow.json')
      end

      def test_empty_assets_without_paging
        stub_request(:get, 'https://graph.facebook.com/v24.0/flow/assets?limit=100').to_return(body: '{"data":[]}')

        page = @client.flows.assets(flow_id: 'flow')

        assert_empty(page.records)
        assert_nil(page.before)
        assert_nil(page.after)
      end

      def test_sets_the_public_key_preserving_pem_newlines_and_base64_characters
        key = "-----BEGIN PUBLIC KEY-----\nTEST+PUBLIC/KEY==\n-----END PUBLIC KEY-----\n"
        request = stub_request(:post, 'https://graph.facebook.com/v24.0/phone/whatsapp_business_encryption')
                  .with(headers: { 'Authorization' => 'Bearer flow-token',
                                   'Content-Type' => 'application/x-www-form-urlencoded' },
                        body: { 'business_public_key' => key })
                  .to_return(body: '{"success":true}').then.to_return(body: '{"success":false}')

        assert(@client.phone_numbers.set_public_key(phone_number_id: 'phone', business_public_key: key))
        refute(@client.phone_numbers.set_public_key(phone_number_id: 'phone', business_public_key: key))
        assert_requested(request, times: 2)
      end

      def test_reads_the_public_key_and_signature_status_without_hiding_a_mismatch
        key = { 'business_public_key' => 'stored-public-key', 'business_public_key_signature_status' => 'MISMATCH' }
        data = { 'data' => [key] }
        request = stub_request(:get, 'https://graph.facebook.com/v24.0/phone/whatsapp_business_encryption')
                  .with(headers: { 'Authorization' => 'Bearer flow-token' }).to_return(body: data.to_json)

        result = @client.phone_numbers.get_public_key(phone_number_id: 'phone')

        assert_equal(data, result)
        assert_equal('MISMATCH', result.dig('data', 0, 'business_public_key_signature_status'))
        assert_requested(request, times: 1)
      end

      def test_preserves_graph_errors_for_assets_and_key_configuration
        body = { error: { message: 'Permission denied', code: 200, type: 'OAuthException' } }.to_json
        assets = stub_request(:get, 'https://graph.facebook.com/v24.0/flow/assets?limit=100')
                 .to_return(status: 403, body: body)
        key = stub_request(:post, 'https://graph.facebook.com/v24.0/phone/whatsapp_business_encryption')
              .to_return(status: 403, body: body)

        error = assert_raises(Responses::HttpResponseError) { @client.flows.assets(flow_id: 'flow') }
        assert_equal(403, error.http_status)
        assert_raises(Responses::HttpResponseError) do
          @client.phone_numbers.set_public_key(phone_number_id: 'phone', business_public_key: 'public-key')
        end
        assert_requested(assets, times: 1)
        assert_requested(key, times: 1)
      end
    end
  end
end
