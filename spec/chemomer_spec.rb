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
    # The engine is 1.0.0; the 4th segment counts this gem's
    # runtime-only revisions (reset at the engine's 1.0.0 major; rides the 1.1.0 engine).
    expect(described_class::VERSION).to match(/\A1\.1\.0\.\d+\z/)
  end

  it "exposes the binding surface" do
    expect(described_class).to respond_to(:from_molfile)
    expect(described_class).to respond_to(:aux_from_molfile)
    expect(described_class).to respond_to(:rinchi_from_rxn)
    expect(described_class).to respond_to(:rinchi_from_rd)
    expect(described_class).to respond_to(:rinchi_decode)
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

    # The reaction-identity surface: same graceful-absence contract as
    # AuxInfo — the specs light up when an engine cdylib ships the
    # chemomer_rinchi_* exports. The corpus gate (spec/corpus_oracle_spec.rb)
    # owns the byte-level gate; these pin the Ruby-side shapes.
    describe "the rinchi surface" do
      WATER_RXN = [
        "$RXN",
        "water-is-water",
        "  chemomer",
        "",
        "  1  1",
        "$MOL",
        "",
        "  AsciiChem",
        "",
        "  1  0  0  0  0  0  0  0  0  0999 V2000",
        "   12.0000   12.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0  0",
        "M  END",
        "$MOL",
        "",
        "  AsciiChem",
        "",
        "  1  0  0  0  0  0  0  0  0  0999 V2000",
        "   12.0000   12.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0  0",
        "M  END",
        ""
      ].join("\n").freeze

      def with_rinchi_exports
        # The probe runs OUTSIDE any expectation, so an engine
        # predating the exports skips the whole example instead of
        # failing its first assertion.
        described_class.rinchi_decode("RInChI=1.00.1S/H2O/h1H2<>H2O/h1H2/d+", "")
        yield
      rescue Chemomer::Error => e
        raise e unless e.message.include?("does not export")

        skip "the cdylib does not export the chemomer_rinchi_* symbols yet — " \
             "the reaction-identity surface lands with the engine exports"
      end

      it "derives the five identity lines from an RXNfile" do
        with_rinchi_exports do
          rinchi, rauxinfo, rinchikey, long_key, web_key = described_class.rinchi_from_rxn(WATER_RXN)
          expect(rinchi).to eq("RInChI=1.00.1S/H2O/h1H2<>H2O/h1H2/d+")
          expect(rauxinfo)
            .to eq("RAuxInfo=1.00.1/0/N:1/rA:1nO/rB:/rC:12,12,0;<>0/N:1/rA:1nO/rB:/rC:12,12,0;")
          expect(rinchikey)
            .to eq("Short-RInChIKey=SA-FUHFF-XLYOFNOQVP-XLYOFNOQVP-UHFFFADPSC-NUHFF-NUHFF-NUHFF-ZZZ")
          expect(long_key)
            .to eq("Long-RInChIKey=SA-FUHFF-XLYOFNOQVPJJNP-UHFFFAOYSA-N--XLYOFNOQVPJJNP-UHFFFAOYSA-N")
          expect(web_key).to eq("Web-RInChIKey=XLYOFNOQVPJJNPIXP-NUHFFFADPSCTJSA")
        end
      end

      it "decodes a RInChI string into the component hash" do
        with_rinchi_exports do
          decoded = described_class.rinchi_decode("RInChI=1.00.1S/H2O/h1H2<>H2O/h1H2/d+")
          expect(decoded["directionality"]).to eq("directional")
          expect(decoded["reactants"]).to eq([
            { "inchi" => "InChI=1S/H2O/h1H2", "aux" => "", "inchikey" => "XLYOFNOQVPJJNP-UHFFFAOYSA-N" }
          ])
          expect(decoded["products"]).to eq(decoded["reactants"])
          expect(decoded["agents"]).to be_empty
        end
      end

      it "raises the engine's last_error on a malformed RXNfile" do
        with_rinchi_exports do
          expect { described_class.rinchi_from_rxn("not an rxnfile") }
            .to raise_error(Chemomer::Error, /\$RXN/)
        end
      end
    end
  end
end
