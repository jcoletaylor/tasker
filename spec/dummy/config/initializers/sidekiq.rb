# frozen_string_literal: true

if Rails.env.test?
  require 'sidekiq/testing'
  Sidekiq::Testing.fake!
end
