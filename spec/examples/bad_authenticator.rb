# BadAuthenticator - Intentionally incomplete authenticator for testing interface validation
# This class is missing required methods to test Tasker's interface validation
class BadAuthenticator
  def initialize(options = {})
    @options = options
  end

  # Missing authenticate! and current_user methods intentionally
  # This should cause interface validation to fail

  private

  attr_reader :options
end
