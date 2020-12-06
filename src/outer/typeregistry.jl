# SPDX-License-Identifier: MPL-2.0
using TypeParsers

struct TypeRegistry
    cache::Dict{String,Type} # TODO cache pruning
    TypeRegistry() = new(Dict())
end

function gettype(registry::TypeRegistry, typename::String)
    cached = get(registry.cache, typename, nothing)
    !isnothing(cached) && return cached
    type = parsetype(typename)
    registry.cache[typename] = type
    return type
end
