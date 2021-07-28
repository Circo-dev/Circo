# SPDX-License-Identifier: MPL-2.0
module Transactions

export Transaction, Write, PropertySelector, SubArraySelector, Inconsistency, commit!

using Plugins
using ..Circo
using ..DistributedIdentities

const TransactionId = UInt64

abstract type Write end

struct PropertyWrite{TValue} <: Write
    propertyname::Symbol
    value::TValue
    PropertyWrite(propertyname, value) = new{typeof(value)}(propertyname, value)
end

struct IdxWrite{TValue} <: Write
    idx::Int
    value::TValue
    IdxWrite(idx, value) = new{typeof(value)}(idx, value)
end

struct SubArrayWrite{TValue} <: Write
    fromidx::Int
    toidx::Int
    value::TValue
    SubArrayWrite(fromidx, toidx, value) = new{typeof(value)}(fromidx, toidx, value)
    SubArrayWrite(subarray::UnitRange{Int}, value) = SubArrayWrite(subarray.start, subarray.stop, value)
end

Write(field::Symbol, value) = PropertyWrite(field, value)
Write(idx::Int, value) = IdxWrite(idx, value)
Write(subarray::UnitRange{Int}, value) = SubArrayWrite(subarray, value)
Write(field1, fieldorsub2, value) = Write(field1, Write(fieldorsub2, value))
Write(field1, field2, fieldorsub3, value) = Write(field1, Write(field2, Write(fieldorsub3, value)))

struct Transaction{TWrites}
    id::TransactionId
    identity::DistributedIdentities.DistIdId
    writes::TWrites
    initiator::Addr
    Transaction(me, writes) = new{typeof(writes)}(rand(TransactionId), distid(me), writes, addr(me))
end

function select(from, write::PropertyWrite)
    return getproperty(from, write.propertyname)
end

function select(from, write::IdxWrite)
    return getindex(from, write.idx)
end

_set!(target, write::PropertyWrite) = setproperty!(target, write.propertyname, write.value)

function _set!(target, write::IdxWrite)
    if length(target) < write.idx
        resize!(target, write.idx)
    end
    target[write.idx] = write.value
end

function apply!(target, write::Union{PropertyWrite, IdxWrite}, service)
    if write.value isa Write
        prop = select(target, write)
        apply!(prop, write.value)
    else
        _set!(target, write)
    end
end

function apply!(target, write::SubArrayWrite, service)
    if length(target) < write.selector.toidx
        resize!(target, write.selector.toidx)
    end
    copyto!(target, write.selector.fromidx, write.value, 1, length(write.value))
end

function apply!(target, writes::Vector, service)
    for write in writes
        apply!(target, write, service) # TODO error handling
    end
end

abstract type ConsistencyStyle end
struct Inconsistency <: ConsistencyStyle end

consistency_style(::Type) = Inconsistency

function commit!(me, writes, service)
    commit!(consistency_style(typeof(me)), me, writes, service)
end

end # module