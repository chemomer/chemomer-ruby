# frozen_string_literal: true

require_relative "lib/chemomer/version"

Gem::Specification.new do |spec|
  spec.name          = "chemomer"
  spec.version       = Chemomer::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Ruby bindings for the chemomer InChI engine — molfile in, identifier / InChIKey out."
  spec.description   = "Chemomer drives the native chemomer engine — the Rust InChI port gated by the " \
                       "shared oracle corpus — through its C ABI via FFI. from_molfile returns the " \
                       "InChI identifier and the InChIKey; aux_from_molfile returns the AuxInfo line. " \
                       "No engine code is vendored: the cdylib is a runtime artifact."
  spec.homepage      = "https://github.com/chemomer/chemomer-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  spec.metadata["source_code_uri"] = "https://github.com/chemomer/chemomer-ruby"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "ffi"
end
