# chemomer

The **Ruby binding for the [chemomer](https://github.com/chemomer/chemomer)
engine** — molfile in, InChI identifier / InChIKey out, driven through
the engine's C ABI with [FFI](https://github.com/ffi/ffi).

```ruby
require "chemomer"

inchi, inchikey = Chemomer.from_molfile(molfile_text)
aux = Chemomer.aux_from_molfile(molfile_text)
Chemomer.ffi_version # => 1
```

A thin wrapper by design: the engine (the byte-exact InChI port, gated
by the shared oracle corpus
[inchi-tests](https://github.com/chemomer/inchi-tests)) lives in the
chemomer repo; this gem owns only the FFI signatures and the packaging
— no engine code is vendored. The cdylib is a runtime artifact: build
it once and point the gem at it.

## The library

The gem resolves the cdylib in this order:

1. `CHEMOMER_LIB` — the path to the built cdylib.
2. The platform default sonames (`libchemomer.dylib` on macOS,
   `libchemomer.so` on Linux), resolved through the loader's search
   path — install the dylib on `LD_LIBRARY_PATH` /
   `DYLD_LIBRARY_PATH` or into a standard lib dir for zero-config use.

Build the cdylib from an engine checkout:

```bash
cargo build --release   # in the chemomer repo
export CHEMOMER_LIB=$PWD/target/release/libchemomer.dylib
```

Errors surface as `Chemomer::Error` — engine failures carry the C
ABI's thread-local `chemomer_last_error` message, resolution failures
carry the remedy.

## Versioning

Runtime packages track the engine: `{engine semver}.{runtime version}`
(the same scheme as chemomer-py). This gem is `0.1.0.1` — engine
`0.1.0`, runtime `1`. An engine bump resets the counter (`0.2.0.1`);
a runtime-only fix increments it (`0.1.0.2`).

## AuxInfo

`aux_from_molfile` needs the `chemomer_aux_from_molfile` C export,
which the engine's 0.1.0 ABI does not ship yet (the Python binding
reaches AuxInfo through the Rust API directly). The gem attaches the
symbol on first use: once an engine cdylib exports it, the method
works with no gem change; against a 0.1.0 cdylib it raises
`Chemomer::Error` saying exactly that.

## Test

```bash
bundle install
CHEMOMER_LIB=$PWD/../chemomer/target/release/libchemomer.dylib bundle exec rspec
```

Specs that need the cdylib gate on `CHEMOMER_LIB` and skip cleanly
without it; the rest run everywhere. CI builds the engine's main
cdylib and runs the full suite on ubuntu + macos.

## Publishing

`release.yml` is dispatch-only: a version input (verified against
`lib/chemomer/version.rb`), the pre-created-tag trick, then
`rubygems/release-gem@v1` — trusted publishing (OIDC), no stored
credentials, no environment.

The first publish of the gem name needs the RubyGems trusted publisher
registered first — gem `chemomer`, owner `chemomer`, repository
`chemomer/chemomer-ruby`, workflow `release.yml`, no environment — or
a local `gem push` for the very first version.

## License

MIT, same as the engine.
