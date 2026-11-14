# frozen_string_literal: true

module Chemomer
  # The reaction-identity layer's decode result, parsed out of the C
  # ABI's component-table wire form — the string the
  # chemomer_rinchi_decode export returns (see
  # RinchiReaction::component_table in the engine's src/rinchi.rs):
  #
  #   <flag>                                  '+' directional, '=' equilibrium
  #   <inchi><TAB><aux><TAB><inchikey>        one line per reactant
  #   <>                                      role separator (bare)
  #   ...
  #
  # InChI, AuxInfo, and InChIKey strings carry no tab and no newline,
  # so the table splits unambiguously: the first line is the flag, the
  # bare `<>` lines separate the three roles, every other line is one
  # component's identity triple. The roles are already resolved (a
  # backward-flag identifier arrives decoded into its real roles), so
  # the flag line reads `+` or `=` only.
  module Rinchi
    DIRECTIONALITY = {
      "+" => "directional",
      "=" => "equilibrium"
    }.freeze

    module_function

    # Parses the component table into the decoded reaction:
    #
    #   { "directionality" => "directional",
    #     "reactants" => [{ "inchi" => ..., "aux" => ..., "inchikey" => ... }, ...],
    #     "products" => [...], "agents" => [...] }
    def decode_table(table)
      lines = table.split("\n")
      lines.pop if lines.last && lines.last.empty?
      flag = lines.shift
      directionality = DIRECTIONALITY.fetch(flag) do
        raise Error, "chemomer: unknown direction flag #{flag.inspect} in the component table"
      end

      roles = { "reactants" => [], "products" => [], "agents" => [] }
      keys = roles.keys
      index = 0
      lines.each do |line|
        if line == "<>"
          index += 1
          next
        end
        key = keys[index] or raise Error, "chemomer: too many role separators in the component table"
        inchi, aux, inchikey = line.split("\t", -1)
        unless inchikey
          raise Error, "chemomer: malformed component line #{line.inspect} in the component table"
        end
        roles[key] << { "inchi" => inchi, "aux" => aux, "inchikey" => inchikey }
      end

      { "directionality" => directionality }.merge(roles)
    end
  end
end
