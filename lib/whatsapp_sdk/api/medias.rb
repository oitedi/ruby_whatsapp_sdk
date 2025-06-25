# frozen_string_literal: true

require "faraday"
require "faraday/multipart"

require_relative "request"
require_relative '../resource/media_types'

module WhatsappSdk
  module Api
    class Medias < Request
      class FileNotFoundError < StandardError
        attr_reader :file_path

        def initialize(file_path:)
          @file_path = file_path

          message = "Couldn't find file_path: #{file_path}"
          super(message)
        end
      end

      class InvalidMediaTypeError < StandardError
        attr_reader :media_type

        def initialize(media_type:)
          @media_type = media_type
          message =  "Invalid Media Type #{media_type}. See the supported types in the official documentation " \
                     "https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media#supported-media-types."
          super(message)
        end
      end

      # Get Media by ID.
      #
      # @param media_id [String] Media Id.
      # @return [Resource::Media] Media object.
      def get(media_id:)
        response = send_request(
          http_method: "get",
          endpoint: "/#{media_id}"
        )

        Resource::Media.from_hash(response)
      end

      def media(media_id:)
        warn "[DEPRECATION] `media` is deprecated. Please use `get` instead."
        get(media_id: media_id)
      end

      # Download Media by URL.
      #
      # @param url URL.
      # @param file_path [String] The file_path to download the media e.g. "tmp/downloaded_image.png".
      # @param media_type [String] The media type e.g. "audio/mp4". See possible types in the official
      #  documentation https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media#supported-media-types,
      #  but note that the API may allow more depending on the client.
      # @return [Boolean] Whether the media was downloaded successfully.
      def download(url:, file_path:, media_type:)
        # Allow download of unsupported media types, since Cloud API may decide to let it through.
        #   https://github.com/ignacio-chiazzo/ruby_whatsapp_sdk/discussions/127
        # raise InvalidMediaTypeError.new(media_type: media_type) unless valid_media_type?(media_type)

        content_type_header = map_media_type_to_content_type_header(media_type)

        response = download_file(url: url, file_path: file_path, content_type_header: content_type_header)

        return true if response.code.to_i == 200

        begin
          body = JSON.parse(response.body)
        rescue JSON::ParserError
          body = { "message" => response.body }
        end

        raise Api::Responses::HttpResponseError.new(http_status: response.code, body: body)
      end

      # Upload a media.
      # @param sender_id [Integer] Sender' phone number.
      # @param file_path [String] Path to the file stored in your local directory. For example: "tmp/whatsapp.png".
      # @param type [String] Media type e.g. text/plain, video/3gp, image/jpeg, image/png. For more information,
      # see the official documentation https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media#supported-media-types.
      #
      # @return [Api::Responses::IdResponse] IdResponse object.
      def upload(sender_id:, file_path:, type:, headers: {})
        raise FileNotFoundError.new(file_path: file_path) unless File.file?(file_path)

        params = {
          messaging_product: "whatsapp",
          file: Faraday::FilePart.new(file_path, type),
          type: type
        }

        response = send_request(
          http_method: "post",
          endpoint: "#{sender_id}/media",
          params: params,
          headers: headers,
          multipart: true
        )

        Api::Responses::IdResponse.new(response["id"])
      end

      # Delete a Media by ID.
      #
      # @param media_id [String] Media Id.
      # @return [Boolean] Whether the media was deleted successfully.
      def delete(media_id:)
        response = send_request(
          http_method: "delete",
          endpoint: "/#{media_id}"
        )

        Api::Responses::SuccessResponse.success_response?(response: response)
      end

      private

      # Create upload session for template media using Graph API
      def create_upload_session(app_id:, file_path:, type:, access_token:)
        file_size = File.size(file_path)

        params = {
          file_length: file_size,
          file_type: type
        }

        # Use Graph API endpoint directly
        connection = Faraday.new(url: "https://graph.facebook.com") do |faraday|
          faraday.request :json
          faraday.response :json
          faraday.adapter Faraday.default_adapter
        end

        response = connection.post("/v23.0/#{app_id}/uploads") do |req|
          req.headers['Authorization'] = "Bearer #{access_token}"
          req.headers['Content-Type'] = 'application/json'
          req.body = params
        end

        raise Api::Responses::HttpResponseError.new(http_status: response.status, body: response.body) unless response.success?

        response.body
      end

      # Upload file to the created session
      def upload_file_to_session(session_id:, file_path:, access_token:)
        # Use Graph API endpoint directly
        connection = Faraday.new(url: "https://graph.facebook.com") do |faraday|
          faraday.response :json
          faraday.adapter Faraday.default_adapter
        end

        file_data = File.binread(file_path)

        response = connection.post("/v23.0/#{session_id}") do |req|
          req.headers['Authorization'] = "Bearer #{access_token}"
          req.headers['file_offset'] = '0'
          req.headers['Content-Type'] = 'application/octet-stream'
          req.body = file_data
        end

        raise Api::Responses::HttpResponseError.new(http_status: response.status, body: response.body) unless response.success?

        response.body
      end

      def map_media_type_to_content_type_header(media_type)
        # Media type maps 1:1 to the content-type header.
        # The list of supported types are in MediaTypes::SUPPORTED_TYPES.
        # It uses the media type defined by IANA https://www.iana.org/assignments/media-types

        media_type
      end

      def valid_media_type?(media_type)
        Resource::MediaTypes::SUPPORTED_MEDIA_TYPES.include?(media_type)
      end
    end
  end
end
