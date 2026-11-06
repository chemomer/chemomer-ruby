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
#   Chemomer.ffi_version                # => 1
module Chemomer
  autoload :VERSION, "chemomer/version"
  autoload :Bindings, "chemomer/bindings"
  autoload :Error, "chemomer/error"

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
    inchi = call(bindings, molfile, :chemomer_from_molfile)
    inchikey = call(bindings, molfile, :chemomer_inchikey)
    [inchi, inchikey]
  end

  # molfile → the AuxInfo line (per-component canonical numbering,
  # reversibility block). Needs the chemomer_aux_from_molfile export —
  # attached on first use, so it lights up the moment an engine cdylib
  # ships it.
  def aux_from_molfile(molfile)
    bindings = Bindings.aux(*lib)
    call(bindings, molfile, :chemomer_aux_from_molfile)
  end

  # The C ABI version of the attached cdylib (1 today).
  def ffi_version
    Bindings.for(*lib).chemomer_ffi_version
  end

  # The C ABI contract: null return on error (the message sits on the
  # calling thread's last_error slot), the returned string freed right
  # after reading it.
  def call(bindings, molfile, function)
    pointer = bindings.public_send(function, molfile)
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
