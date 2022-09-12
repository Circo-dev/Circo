# SPDX-License-Identifier: MPL-2.0
module Marshal

using ..Circo
using TypeParsers
using MsgPack

export marshal, unmarshal, TypeRegistry

MsgPack.msgpack_type(::DataType) = MsgPack.StructType() # TODO use StructTypes.jl or an abstract type

MsgPack.msgpack_type(::Type{ActorId}) = MsgPack.StringType()
MsgPack.to_msgpack(::MsgPack.StringType, id::ActorId) = string(id, base=16)
MsgPack.from_msgpack(::Type{ActorId}, str::AbstractString) = parse(ActorId, str;base=16)

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

function marshal(data, buf=IOBuffer())
    println(buf, typeof(data))
    write(buf, pack(data))
    return buf
end

function unmarshal(buf, typeregistry, msg_type_name)
    length(buf) > 0 || return nothing
    typename = ""
    try
        io = IOBuffer(buf)
        typename = msg_type_name * readline(io)
        type = gettype(typeregistry, typename)
        return unpack(io, type)
    catch e
        if e isa UndefVarError
             @warn "Type $typename is not known"
        else
            rethrow(e)
        end
    end
    return nothing
end

end # module
