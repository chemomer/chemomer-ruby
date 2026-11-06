# frozen_string_literal: true

require "spec_helper"

RSpec.describe Chemomer do
  # The engine's own V2000 water fixture (chemomer/src/ffi.rs).
  WATER = [
    "water",
    "  AsciiChem",
    "",
    "  1  0  0  0  0  0  0  0  0  0999 V2000",
    "   12.0000   12.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0  0",
    "M  END",
    ""
  ].join("\n").freeze

  it "ships the {engine semver}.{runtime version}" do
    expect(described_class::VERSION).to eq("0.1.0.1")
  end

  it "exposes the binding surface" do
    expect(described_class).to respond_to(:from_molfile)
    expect(described_class).to respond_to(:aux_from_molfile)
    expect(described_class).to respond_to(:ffi_version)
  end

  it "refuses an unreadable library path" do
    expect { Chemomer::Bindings.for("/nonexistent/libchemomer.so") }
      .to raise_error(Chemomer::Error, /not readable/)
  end

  # The real-library check mirrors the native_engine spec of
  # asciichem-ruby: set CHEMOMER_LIB to the built cdylib (cargo build
  # --release in the chemomer checkout) to run it. CI does exactly
  # that; without the variable the group skips so the suite stays
  # green on any machine.
  lib = ENV.fetch("CHEMOMER_LIB", nil)
  next unless lib

  describe "against a built cdylib" do
    it "resolves the configured library" do
      expect(described_class.lib).to eq([lib])
    end

    it "derives the water identity" do
      expect(described_class.from_molfile(WATER))
        .to eq(["InChI=1S/H2O/h1H2", "XLYOFNOQVPJJNP-UHFFFAOYSA-N"])
    end

    it "reports the C ABI version" do
      expect(described_class.ffi_version).to eq(1)
    end

    it "raises the engine's last_error on a malformed molfile" do
      expect { described_class.from_molfile("not a molfile") }
        .to raise_error(Chemomer::Error)
    end

    it "derives the water AuxInfo line when the cdylib exports it" do
      begin
        aux = described_class.aux_from_molfile(WATER)
      rescue Chemomer::Error => e
        raise e unless e.message.include?("chemomer_aux_from_molfile")

        skip "the cdylib does not export chemomer_aux_from_molfile yet — " \
             "AuxInfo lands with the engine export"
      end
      expect(aux).to eq("AuxInfo=1/0/N:1/rA:1nO/rB:/rC:12,12,0;")
    end
  end
end
