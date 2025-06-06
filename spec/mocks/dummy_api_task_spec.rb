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
    let(:handler_config) { Tasker::StepHandler::Api::Config.new(url: 'https://api.example.com', jitter_factor: 1) }
    let(:handler) { DummyApiTask::Handler.new(config: handler_config) }
    let(:task) { task_handler.initialize_task!(helper.task_request) }
    let(:sequence) { task_handler.get_sequence(task) }
    let(:step) { sequence.steps.first }

    before do
      allow(handler).to receive(:connection).and_return(connection)
    end

    describe 'successful API calls' do
      it 'processes successful responses' do
        # Use proper Faraday test stub format: [status, headers, body]
        stubs.get("/?step_name=#{step.name}") do
          [200, { 'Content-Type' => 'application/json' }, '{"data": "successful response"}']
        end

        handler.handle(task, sequence, step)

        # API handler stores Faraday::Response, but ActiveRecord serializes it to hash for jsonb storage
        expect(step.results).to be_a(Hash)
        expect(step.results['status']).to eq(200)
        expect(step.results['response_headers']['Content-Type']).to eq('application/json')
        expect(step.results['body']).to eq('{"data": "successful response"}')
      end

      it 'handles successful responses with different status codes' do
        [200, 201, 202, 204].each do |status|
          # Use proper Faraday test stub format
          stubs.get("/?step_name=#{step.name}") do
            [status, { 'Content-Type' => 'application/json' }, status == 204 ? nil : '{"data": "successful response"}']
          end

          handler.handle(task, sequence, step)

          # Verify ActiveRecord-serialized response hash is stored
          expect(step.results).to be_a(Hash)
          expect(step.results['status']).to eq(status)
          expect(step.results['response_headers']['Content-Type']).to eq('application/json')
          expect(step.results['body']).to eq(status == 204 ? nil : '{"data": "successful response"}')
        end
      end
    end

    describe 'retry and backoff behavior' do
      context 'when receiving a 429 Too Many Requests response' do
        context 'with Retry-After header' do
          it 'uses the Retry-After value for backoff' do
            stubs.get("/?step_name=#{step.name}") do
              [429, { 'Retry-After' => '30' }, '{"error": "Too many requests"}']
            end

            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to eq(30)
          end

          it 'parses Retry-After HTTP date format' do
            retry_after = (Time.zone.now + 60).httpdate
            stubs.get("/?step_name=#{step.name}") do
              [429, { 'Retry-After' => retry_after }, '{"error": "Too many requests"}']
            end

            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to be_between(1, 60)
          end
        end

        context 'without Retry-After header' do
          it 'applies exponential backoff' do
            stubs.get("/?step_name=#{step.name}") do
              [429, {}, '{"error": "Too many requests"}']
            end

            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to eq(4) # Initial delay
          end

          it 'increases backoff with each attempt' do
            stubs.get("/?step_name=#{step.name}") do
              [429, {}, '{"error": "Too many requests"}']
            end

            step.attempts = 2
            expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
            expect(step.backoff_request_seconds).to eq(8)
          end
        end
      end

      context 'when receiving a 503 Service Unavailable response' do
        it 'applies exponential backoff' do
          stubs.get("/?step_name=#{step.name}") do
            [503, {}, '{"error": "Service unavailable"}']
          end

          expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
          expect(step.backoff_request_seconds).to eq(4)
        end
      end

      context 'when receiving other error responses' do
        it 'does not apply backoff' do
          stubs.get("/?step_name=#{step.name}") do
            [500, {}, '{"error": "Internal server error"}']
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
            [429, {}, '{"error": "Too many requests"}']
          end

          expect { handler.handle(task, sequence, step) }.to raise_error(Faraday::Error)
          expect(step.backoff_request_seconds).to be_nil
        end
      end
    end
  end
end
