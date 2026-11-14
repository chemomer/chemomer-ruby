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

  # The reaction-identity transport, gated by the same corpus's RInChI
  # tranche (rinchi-reactions.json): the RXNfile/RDfile input edges
  # assemble the recorded oracle lines byte-for-byte, and the decode
  # direction reads every recorded RInChI string back into its
  # components. Graceful absence: an engine cdylib predating the
  # chemomer_rinchi_* exports skips the tranche with a report — the
  # gate lights up at the next engine ride. The equilibrium family is
  # recorded under the oracle's /force-equilibrium flag, which the C
  # ABI carries no entry for; its four cases gate through the DECODE
  # direction (the recorded string decodes to equilibrium) and are
  # reported as derive-skips. The RDfile edge exports the identifier
  # line only — the other four lines ride the RXN exports' assembly,
  # and the engine's CI owns the full per-line gate.
  it "byte-compares every rinchi fixture through the dylib" do
    path = File.join(corpus, "corpus", "fixtures", "rinchi-reactions.json")
    skip "the corpus pin predates the rinchi tranche" unless File.file?(path)
    cases = JSON.parse(File.read(path))
    expect(cases).not_to be_empty

    begin
      Chemomer.rinchi_decode("RInChI=1.00.1S/H2O/h1H2<>H2O/h1H2/d+", "")
    rescue Chemomer::Error => e
      if e.message.include?("does not export")
        skip "the engine cdylib predates the chemomer_rinchi_* exports — lights up at the next engine ride"
      end
      raise
    end

    failures = []
    ran = 0
    derive_skips = []
    cases.each do |case_data|
      id = "rinchi-reactions/#{case_data['id']}"

      # The decode direction: every recorded identifier (plus its
      # RAuxInfo companion) reads back into the recorded per-component
      # identity triples — compared order-free (the reader resolves
      # roles from the direction flag; within a role the wire order is
      # the assembly's sorted order).
      begin
        decoded = Chemomer.rinchi_decode(case_data["rinchi"], case_data["rauxinfo"] || "")
      rescue Chemomer::Error => e
        failures << "#{id}: decode raised #{e.message[0, 80]}"
        next
      end
      ran += 1
      decoded_triples = decoded.values_at("reactants", "products", "agents")
                                .flatten(1)
                                .map { |component| component.values_at("inchi", "aux", "inchikey") }
                                .sort
      recorded_triples = case_data["components"]
                         .map { |component| component.values_at("inchi", "aux", "inchikey") }
                         .sort
      unless decoded_triples == recorded_triples
        failures << "#{id}: decoded components differ from the oracle"
      end
      expected_directionality = case_data["forceEquilibrium"] ? "equilibrium" : "directional"
      unless decoded["directionality"] == expected_directionality
        failures << "#{id}: directionality #{decoded['directionality'].inspect} != #{expected_directionality.inspect}"
      end

      # The derive direction: the recorded input edge assembles the
      # recorded output lines byte-for-byte (keys compared headerless —
      # the corpus records them without their headers).
      if case_data["forceEquilibrium"]
        derive_skips << id
      elsif case_data["rxnfile"]
        begin
          rinchi, rauxinfo, rinchikey, long_key, web_key = Chemomer.rinchi_from_rxn(case_data["rxnfile"])
        rescue Chemomer::Error => e
          failures << "#{id}: raised #{e.message[0, 80]}"
          next
        end
        ran += 1
        compare(failures, id, "rinchi", rinchi, case_data["rinchi"])
        compare(failures, id, "rauxinfo", rauxinfo, case_data["rauxinfo"])
        compare(failures, id, "rinchikey", strip_header(rinchikey, "Short-RInChIKey="), case_data["rinchikey"])
        compare(failures, id, "longKey", strip_header(long_key, "Long-RInChIKey="), case_data["longKey"])
        compare(failures, id, "webKey", strip_header(web_key, "Web-RInChIKey="), case_data["webKey"])
      elsif case_data["rdfile"]
        begin
          rinchi = Chemomer.rinchi_from_rd(case_data["rdfile"])
        rescue Chemomer::Error => e
          failures << "#{id}: raised #{e.message[0, 80]}"
          next
        end
        ran += 1
        compare(failures, id, "rinchi", rinchi, case_data["rinchi"])
      end
    end

    puts "rinchi gate: #{ran} comparisons, #{failures.length} failures, " \
         "#{derive_skips.length} derive-skips (force-equilibrium: #{derive_skips.join(', ')})"
    expect(failures).to be_empty, failures.first(20).join("\n")
  end

  def compare(failures, id, what, actual, recorded)
    return unless recorded
    return if actual == recorded

    failures << "#{id}: #{what} #{actual.inspect} != #{recorded.inspect}"
  end

  def strip_header(line, header)
    line.delete_prefix(header)
  end
end
