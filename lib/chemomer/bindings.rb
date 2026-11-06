# frozen_string_literal: true

module Chemomer
  # The FFI surface of the chemomer cdylib: one anonymous module per
  # library (attach_function binds the symbols once), cached per
  # candidate list — the shape of asciichem-ruby's NativeEngine.
  #
  # The documented C ABI of chemomer 0.1.0:
  #
  #   chemomer_from_molfile  molfile → identifier string (null on error)
  #   chemomer_inchikey      molfile → InChIKey string (null on error)
  #   chemomer_string_free   releases a string returned by the ABI
  #   chemomer_last_error    → the calling thread's last error, or null
  #   chemomer_ffi_version   → the ABI version (1)
  module Bindings
    module_function

    # The main surface: attaches eagerly (every symbol is part of the
    # documented ABI) and caches per candidate list.
    def for(*names)
      bindings[names] ||= attach(names)
    end

    # AuxInfo: the 0.1.0 ABI does not export chemomer_aux_from_molfile
    # (the Python binding reaches AuxInfo through the Rust API
    # directly). The symbol is attached on first use, so the gem
    # lights up without a change the moment an engine cdylib ships the
    # export; against a dylib without it, a clear Chemomer::Error
    # explains the gap.
    def aux(*names)
      aux_bindings[names] ||= attach_aux(names)
    end

    def bindings
      @bindings ||= {}
    end

    def aux_bindings
      @aux_bindings ||= {}
    end

    def attach(names)
      guard_readable(names)
      Module.new do
        extend FFI::Library

        ffi_lib(*names)
        attach_function :chemomer_from_molfile, %i[string], :pointer
        attach_function :chemomer_inchikey, %i[string], :pointer
        attach_function :chemomer_string_free, %i[pointer], :void
        attach_function :chemomer_last_error, [], :pointer
        attach_function :chemomer_ffi_version, [], :uint32

        # The message of the last error on the calling thread, or nil.
        def self.last_error
          pointer = chemomer_last_error
          pointer.null? ? nil : pointer.read_string
        end
      end
    rescue LoadError => e
      raise Error, load_failure(e)
    end

    def attach_aux(names)
      guard_readable(names)
      Module.new do
        extend FFI::Library

        ffi_lib(*names)
        attach_function :chemomer_aux_from_molfile, %i[string], :pointer
        # The call path needs the companions too — they exist in every
        # engine ABI version, so attaching them here is version-safe;
        # only the aux symbol above is the version-sensitive one.
        attach_function :chemomer_string_free, %i[pointer], :void
        attach_function :chemomer_last_error, [], :pointer

        def self.last_error
          pointer = chemomer_last_error
          pointer.null? ? nil : pointer.read_string
        end
      end
    rescue FFI::NotFoundError
      raise Error,
            "chemomer: the cdylib does not export chemomer_aux_from_molfile — " \
            "AuxInfo needs an engine that ships the export " \
            "(github.com/chemomer/chemomer, src/ffi.rs)"
    rescue LoadError => e
      raise Error, load_failure(e)
    end

    # An explicit CHEMOMER_LIB path is one candidate; a missing or
    # unreadable file deserves the direct message rather than the
    # loader's. The default soname list is searched by the loader
    # instead — nothing to check here.
    def guard_readable(names)
      return unless names.one?

      path = names.first
      return if File.readable?(path)

      raise Error,
            "chemomer: #{path} is not readable — set CHEMOMER_LIB to the built " \
            "cdylib (cargo build --release in the chemomer checkout)"
    end

    def load_failure(error)
      "chemomer: could not load the cdylib (#{error.message}). Set CHEMOMER_LIB " \
        "to the built cdylib (cargo build --release in the chemomer checkout) or " \
        "install it on the loader path."
    end
  end
end
