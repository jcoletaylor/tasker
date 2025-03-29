# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../helpers/task_helpers'
require_relative 'dummy_api_task'

module Tasker
  RSpec.describe(DummyApiTask) do
    let(:helper) { Helpers::ApiTaskHelpers.new }
    let(:task_handler) { helper.factory.get(Helpers::ApiTaskHelpers::DUMMY_API_TASK) }
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) { Faraday.new { |b| b.adapter(:test, stubs) } }
    let(:handler) { DummyApiTask::Handler.new(config: Tasker::StepHandler::Api::Config.new(url: 'https://api.example.com')) }
    let(:task) { task_handler.initialize_task!(helper.task_request) }
    let(:sequence) { task_handler.get_sequence(task) }
    let(:step) { sequence.steps.first }

    before do
      allow(handler).to receive(:connection).and_return(connection)
    end

    def stub_response(status:, headers: {}, body: '{}')
      Faraday::Response.new(
        Faraday::Env.from(
          status: status,
          response_headers: headers,
          body: body,
          url: "http://api.example.com/?step_name=#{step.name}"
        )
      )
    end

    def create_error_response(status:, body: '{}', headers: {})
      response = Faraday::Response.new(
        Faraday::Env.from(
          status: status,
          body: body,
          response_headers: headers,
          url: "http://api.example.com/?step_name=#{step.name}"
        )
      )

      error_class = case status
                    when 429
                      Faraday::TooManyRequestsError
                    when 503
                      Faraday::ServerError
                    else
                      Faraday::ClientError
                    end

      error = error_class.new(nil, response)
      error.instance_variable_set(:@response, response)
      raise error
    end

    describe 'successful API calls' do
      it 'processes successful responses' do
        response = stub_response(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: '{"data": "successful response"}'
        )

        stubs.get("/?step_name=#{step.name}") do
          response
        end

        handler.handle(task, sequence, step)
        expect(step.results['status']['status']).to eq(200)
        expect(step.results['status']['response_headers']).to eq({ 'Content-Type' => 'application/json' })
        expect(step.results['status']['body']).to eq('{"data": "successful response"}')
      end

      it 'handles successful responses with different status codes' do
        [200, 201, 202, 204].each do |status|
          response = stub_response(
            status: status,
            headers: { 'Content-Type' => 'application/json' },
            body: status == 204 ? nil : '{"data": "successful response"}'
          )

          stubs.get("/?step_name=#{step.name}") do
            response
          end

          handler.handle(task, sequence, step)
          expect(step.results['status']['status']).to eq(status)
          expect(step.results['status']['response_headers']).to eq({ 'Content-Type' => 'application/json' })
          expect(step.results['status']['body']).to eq(status == 204 ? nil : '{"data": "successful response"}')
        end
      end
    end

    describe 'retry and backoff behavior' do
      context 'when receiving a 429 Too Many Requests response' do
        context 'with Retry-After header' do
          it 'uses the Retry-After value for backoff' do
            stubs.get("/?step_name=#{step.name}") do
              create_error_response(
                status: 429,
                headers: { 'Retry-After' => '30' },
                body: '{"error": "Too many requests"}'
              )
            end

            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to eq(30)
          end

          it 'parses Retry-After HTTP date format' do
            retry_after = (Time.zone.now + 60).httpdate
            stubs.get("/?step_name=#{step.name}") do
              create_error_response(
                status: 429,
                headers: { 'Retry-After' => retry_after },
                body: '{"error": "Too many requests"}'
              )
            end

            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to be_within(1).of(60)
          end
        end

        context 'without Retry-After header' do
          it 'applies exponential backoff' do
            stubs.get("/?step_name=#{step.name}") do
              create_error_response(
                status: 429,
                headers: {},
                body: '{"error": "Too many requests"}'
              )
            end

            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to eq(2) # Initial delay
          end

          it 'increases backoff with each attempt' do
            stubs.get("/?step_name=#{step.name}") do
              create_error_response(
                status: 429,
                headers: {},
                body: '{"error": "Too many requests"}'
              )
            end

            step.attempts = 2
            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to eq(50) # 2 * 5^2
          end
        end
      end

      context 'when receiving a 503 Service Unavailable response' do
        it 'applies exponential backoff' do
          stubs.get("/?step_name=#{step.name}") do
            create_error_response(
              status: 503,
              headers: {},
              body: '{"error": "Service unavailable"}'
            )
          end

          expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
          expect(step.backoff_request_seconds).to eq(2) # Initial delay
        end
      end

      context 'when receiving other error responses' do
        it 'does not apply backoff' do
          stubs.get("/?step_name=#{step.name}") do
            create_error_response(
              status: 500,
              headers: {},
              body: '{"error": "Internal server error"}'
            )
          end

          expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
          expect(step.backoff_request_seconds).to be_nil
        end
      end

      context 'when exponential backoff is disabled' do
        let(:handler) do
          DummyApiTask::Handler.new(
            config: Tasker::StepHandler::Api::Config.new(
              url: 'https://api.example.com',
              enable_exponential_backoff: false
            )
          )
        end

        it 'does not apply exponential backoff' do
          stubs.get("/?step_name=#{step.name}") do
            create_error_response(
              status: 429,
              headers: {},
              body: '{"error": "Too many requests"}'
            )
          end

          expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
          expect(step.backoff_request_seconds).to be_nil
        end
      end
    end
  end
end
