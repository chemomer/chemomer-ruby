# frozen_string_literal: true

module Chemomer
  # The {engine semver}.{runtime version} scheme (shared with
  # chemomer-py): the chemomer engine release this gem wraps (0.1.0)
  # plus the gem's own runtime counter (1). An engine bump resets the
  # counter (0.2.0.1); a runtime-only fix increments it (0.1.0.2).
  VERSION = "1.1.0.0"
end
