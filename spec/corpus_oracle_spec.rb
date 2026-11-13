# frozen_string_literal: true

require "json"
require "spec_helper"

# The FFI transport, gated by the inchi-tests oracle corpus. Every
# identity fixture's molfile goes through the loaded dylib; the
# returned identifier / AuxInfo / InChIKey byte-compare against the
# recorded oracle. Skips without CHEMOMER_LIB (the rest of the suite's
# contract); CI sets both variables. The corpus is never edited to
# make the binding pass — the engine's CI owns the same gate; this one
# exists because the transport across the FFI boundary is where drift
# would appear, and smoke specs don't cover it.
corpus = ENV.fetch("INCHI_TESTS", nil)

RSpec.describe "chemomer FFI transport vs the inchi-tests oracle" do
  before do
    skip "INCHI_TESTS not set (clone chemomer/inchi-tests; CI gates this)" unless corpus
    skip "CHEMOMER_LIB not set (build the cdylib; CI gates this)" unless ENV["CHEMOMER_LIB"]
    unless File.directory?(File.join(corpus, "corpus", "fixtures"))
      skip "inchi-tests corpus fixtures not found at #{corpus}"
    end
  end

  it "byte-compares every identity fixture through the dylib" do
    fixtures = Dir[File.join(corpus, "corpus", "fixtures", "identity-*.json")].sort
    expect(fixtures).not_to be_empty

    failures = []
    ran = 0
    fixtures.each do |path|
      JSON.parse(File.read(path)).each do |case_data|
        id = "#{File.basename(path, '.json')}/#{case_data['id']}"
        begin
          inchi, key = Chemomer.from_molfile(case_data["molfile"])
          aux = Chemomer.aux_from_molfile(case_data["molfile"])
        rescue Chemomer::Error => e
          failures << "#{id}: raised #{e.message[0, 80]}"
          next
        end
        ran += 1
        # Compare only fields the fixture records (identity-metal2
        # carries no aux layer) — a missing oracle field is not a gate.
        failures << "#{id}: inchi #{inchi.inspect} != #{case_data['inchi'].inspect}" if case_data["inchi"] && inchi != case_data["inchi"]
        failures << "#{id}: aux #{aux.inspect} != #{case_data['aux'].inspect}" if case_data["aux"] && aux != case_data["aux"]
        failures << "#{id}: key #{key.inspect} != #{case_data['inchikey'].inspect}" if case_data["inchikey"] && key != case_data["inchikey"]
      end
    end

    puts "oracle gate: #{ran} cases byte-compared, #{failures.length} failures"
    expect(failures).to be_empty, failures.first(20).join("\n")
  end
end
