# frozen_string_literal: true

module Chemomer
  # The single error type of the gem: engine failures (raised from the
  # C ABI's thread-local last_error) and library-resolution failures
  # alike, so callers rescue one thing.
  class Error < StandardError; end
end
