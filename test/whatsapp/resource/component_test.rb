# typed: true
# frozen_string_literal: true

require "test_helper"
require 'resource/parameter_object'
require 'resource/media'
require 'resource/date_time'
require 'resource/currency'
require 'resource/component'

module WhatsappSdk
  module Resource
    module Resource
      class ComponentTest < Minitest::Test
        def test_button_index_is_set_to_0_by_default
          button_component = Component.new(type: Component::Type::BUTTON, sub_type: Component::Subtype::QUICK_REPLY)
          assert_equal(0, button_component.index)
        end

        def test_validation
          error = assert_raises(Component::InvalidField) do
            Component.new(type: Component::Type::HEADER, sub_type: Component::Subtype::QUICK_REPLY)
          end
          assert_equal("sub_type is not required when type is not button", error.message)
          assert_equal(:sub_type, error.field)

          error = assert_raises(Component::InvalidField) do
            Component.new(type: Component::Type::HEADER, index: 0)
          end
          assert_equal("index is not required when type is not button", error.message)
          assert_equal(:index, error.field)
        end

        def test_add_parameters
          image = MediaComponent.new(type: MediaComponent::Type::IMAGE,
                                     link: "http(s)://URL", caption: "caption")
          document = MediaComponent.new(type: MediaComponent::Type::DOCUMENT,
                                        link: "http(s)://URL", filename: "txt.rb")
          video = MediaComponent.new(type: MediaComponent::Type::VIDEO, id: "123")
          currency = Currency.new(code: "USD", amount: 1000, fallback_value: "1000")
          date_time = DateTime.new(fallback_value: "2020-01-01T00:00:00Z")

          parameter_text = ParameterObject.new(type: ParameterObject::Type::TEXT, text: "I am a text")
          parameter_currency = ParameterObject.new(type: ParameterObject::Type::CURRENCY, currency: currency)
          parameter_date_time = ParameterObject.new(type: ParameterObject::Type::DATE_TIME, date_time: date_time)
          parameter_image = ParameterObject.new(type: ParameterObject::Type::IMAGE, image: image)
          parameter_document = ParameterObject.new(type: ParameterObject::Type::DOCUMENT, document: document)
          parameter_video = ParameterObject.new(type: ParameterObject::Type::VIDEO, video: video)

          header_component = Component.new(type: Component::Type::HEADER)

          header_component.add_parameter(parameter_text)
          header_component.add_parameter(parameter_currency)
          header_component.add_parameter(parameter_date_time)
          header_component.add_parameter(parameter_image)
          header_component.add_parameter(parameter_document)
          header_component.add_parameter(parameter_video)
          header_component.add_parameter(parameter_date_time)

          assert_equal(
            [
              parameter_text, parameter_currency, parameter_date_time, parameter_image,
              parameter_document, parameter_video, parameter_date_time
            ],
            header_component.parameters
          )
        end

        def test_to_json_header_component
          image = MediaComponent.new(type: MediaComponent::Type::IMAGE, link: "http(s)://URL", caption: "caption")
          parameter_image = ParameterObject.new(type: ParameterObject::Type::IMAGE, image: image)

          header_component = Component.new(
            type: Component::Type::HEADER,
            parameters: [parameter_image]
          )

          assert_equal(
            {
              type: "header",
              parameters: [
                {
                  type: "image",
                  image: {
                    link: "http(s)://URL",
                    caption: "caption"
                  }
                }
              ]
            },
            header_component.to_json
          )
        end

        def test_to_json_body_component
          parameter_text = ParameterObject.new(type: ParameterObject::Type::TEXT, text: "I am a text")

          currency = Currency.new(code: "USD", amount: 1000, fallback_value: "1000")
          parameter_currency = ParameterObject.new(type: ParameterObject::Type::CURRENCY, currency: currency)

          date_time = DateTime.new(fallback_value: "2020-01-01T00:00:00Z")
          parameter_date_time = ParameterObject.new(type: ParameterObject::Type::DATE_TIME, date_time: date_time)

          body_component = Component.new(
            type: Component::Type::BODY,
            parameters: [parameter_text, parameter_currency, parameter_date_time]
          )

          assert_equal(
            {
              type: "body",
              parameters: [
                {
                  type: "text",
                  text: "I am a text"
                },
                {
                  type: "currency",
                  currency: {
                    fallback_value: "1000",
                    code: "USD",
                    amount_1000: 1000
                  }
                },
                {
                  type: "date_time",
                  date_time: {
                    fallback_value: "2020-01-01T00:00:00Z"
                  }
                }
              ]
            },
            body_component.to_json
          )
        end

        def test_to_json_button_component
          button_component = Component.new(
            type: Component::Type::BUTTON,
            index: 0,
            sub_type: Component::Subtype::QUICK_REPLY,
            parameters: [
              ButtonParameter.new(type: ButtonParameter::Type::PAYLOAD, payload: "payload"),
              ButtonParameter.new(type: ButtonParameter::Type::TEXT, text: "text")
            ]
          )

          assert_equal(
            { type: "button", parameters: [{ type: "payload", payload: "payload" }, { type: "text", text: "text" }],
              sub_type: "quick_reply", index: 0 },
            button_component.to_json
          )
        end
      end
    end
  end
end
