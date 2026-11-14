# frozen_string_literal: true

require "ffi"
require "rbconfig"

# Chemomer drives the native chemomer engine — the Rust InChI port
# gated by the shared oracle corpus (chemomer/chemomer) — through its
# C ABI via FFI. A thin wrapper by design: no engine code is vendored,
# the gem owns only the FFI signatures and the packaging. The cdylib
# is a runtime artifact: build it once from an engine checkout and
# point CHEMOMER_LIB at it, or install it on the loader path for the
# default soname resolution.
#
#   Chemomer.from_molfile(molfile)      # => [inchi, inchikey]
#   Chemomer.aux_from_molfile(molfile)  # => aux line
#   Chemomer.rinchi_from_rxn(rxnfile)   # => [rinchi, rauxinfo, short, long, web]
#   Chemomer.rinchi_from_rd(rdfile)     # => rinchi line
#   Chemomer.rinchi_decode(rinchi, rauxinfo)  # => decoded reaction hash
#   Chemomer.ffi_version                # => 1
module Chemomer
  autoload :VERSION, "chemomer/version"
  autoload :Bindings, "chemomer/bindings"
  autoload :Error, "chemomer/error"
  autoload :Rinchi, "chemomer/rinchi"

  # Fallback sonames tried in order when CHEMOMER_LIB is unset; the
  # OS loader resolves them from its search path (LD_LIBRARY_PATH /
  # DYLD_LIBRARY_PATH, /usr/local/lib, ...).
  DEFAULT_LIB_NAMES = {
    darwin: %w[libchemomer.dylib chemomer.dylib],
    linux: %w[libchemomer.so chemomer.so],
    windows: %w[chemomer.dll libchemomer.dll]
  }.freeze

  module_function

  # The library candidates to attach: CHEMOMER_LIB when set, else
  # this platform's default sonames.
  def lib
    env = ENV.fetch("CHEMOMER_LIB", nil)
    env ? [env] : DEFAULT_LIB_NAMES.fetch(platform)
  end

  # molfile → [InChI identifier, InChIKey].
  #
  #   Chemomer.from_molfile(water_molfile)
  #   # => ["InChI=1S/H2O/h1H2", "XLYOFNOQVPJJNP-UHFFFAOYSA-N"]
  def from_molfile(molfile)
    bindings = Bindings.for(*lib)
    inchi = call(bindings, :chemomer_from_molfile, molfile)
    inchikey = call(bindings, :chemomer_inchikey, molfile)
    [inchi, inchikey]
  end

  # molfile → the AuxInfo line (per-component canonical numbering,
  # reversibility block). Needs the chemomer_aux_from_molfile export —
  # attached on first use, so it lights up the moment an engine cdylib
  # ships it.
  def aux_from_molfile(molfile)
    bindings = Bindings.aux(*lib)
    call(bindings, :chemomer_aux_from_molfile, molfile)
  end

  # RXNfile → the reaction-identity five lines: [RInChI, RAuxInfo,
  # Short-RInChIKey, Long-RInChIKey, Web-RInChIKey] (engine-verbatim,
  # key headers included). Needs the chemomer_rinchi_* exports —
  # attached on first use, so they light up the moment an engine
  # cdylib ships them.
  #
  #   Chemomer.rinchi_from_rxn(rxnfile)
  #   # => ["RInChI=1.00.1S/H2O/h1H2<>H2O/h1H2/d+",
  #   #     "RAuxInfo=1.00.1/...",
  #   #     "Short-RInChIKey=SA-FUHFF-...",
  #   #     "Long-RInChIKey=SA-FUHFF-...",
  #   #     "Web-RInChIKey=XLYOFNOQVPJJNPIXP-NUHFFFADPSCTJSA"]
  def rinchi_from_rxn(rxnfile)
    bindings = Bindings.rinchi(*lib)
    [
      call(bindings, :chemomer_rinchi_from_rxn, rxnfile),
      call(bindings, :chemomer_rinchi_aux_from_rxn, rxnfile),
      call(bindings, :chemomer_rinchi_short_key_from_rxn, rxnfile),
      call(bindings, :chemomer_rinchi_long_key_from_rxn, rxnfile),
      call(bindings, :chemomer_rinchi_web_key_from_rxn, rxnfile)
    ]
  end

  # RDfile → the RInChI identifier line (the `$DATUM $MFMT` agent-scan
  # input edge; the other four lines ride the RXN exports' assembly).
  def rinchi_from_rd(rdfile)
    bindings = Bindings.rinchi(*lib)
    call(bindings, :chemomer_rinchi_from_rd, rdfile)
  end

  # RInChI (+ RAuxInfo companion, empty when unknown) → the decoded
  # reaction: { "directionality" => "directional"|"equilibrium",
  # "reactants"|"products"|"agents" => [{"inchi" =>, "aux" =>,
  # "inchikey" =>}, ...] }. No structures are rebuilt — the components
  # carry their identities straight from the string.
  def rinchi_decode(rinchi, rauxinfo = "")
    bindings = Bindings.rinchi(*lib)
    Rinchi.decode_table(call(bindings, :chemomer_rinchi_decode, rinchi, rauxinfo))
  end

  # The C ABI version of the attached cdylib (1 today).
  def ffi_version
    Bindings.for(*lib).chemomer_ffi_version
  end

  # The C ABI contract: null return on error (the message sits on the
  # calling thread's last_error slot), the returned string freed right
  # after reading it.
  def call(bindings, function, *arguments)
    pointer = bindings.public_send(function, *arguments)
    # A null return arrives as a non-nil FFI::Pointer whose address is
    # 0 — the truthiness test would sail past it, so null? is the
    # guard.
    if pointer.nil? || pointer.null?
      raise Error, "chemomer: #{bindings.last_error || 'call failed'}"
    end
    value = pointer.read_string
    bindings.chemomer_string_free(pointer)
    value
  end
  private_class_method :call

  def platform
    case RbConfig::CONFIG["host_os"]
    when /darwin/ then :darwin
    when /linux/ then :linux
    when /mswin|mingw|cygwin/ then :windows
    else
      raise Error,
            "chemomer: no default soname for #{RbConfig::CONFIG['host_os']} — " \
            "set CHEMOMER_LIB to the built cdylib"
    end
  end
  private_class_method :platform
end
