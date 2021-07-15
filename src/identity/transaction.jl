# SPDX-License-Identifier: MPL-2.0
module Transactions

export Transaction, Write, PropertySelector, SubArraySelector, Inconsistency, commit!

using Plugins
using ..Circo
using ..DistributedIdentities

const TransactionId = UInt64

struct PropertySelector
    propertyname::Symbol
end

struct IdxSelector
    idx::Int
end

struct SubArraySelector
    fromidx::Int
    toidx::Int
    SubArraySelector(fromidx, toidx) = new(fromidx, toidx)
    SubArraySelector(subarray::UnitRange{Int}) = SubArraySelector(subarray.start, subarray.stop)
end

struct Write{TSelector, TValue}
    selector::TSelector
    value::TValue
    Write(selector, value) = new{typeof(selector), typeof(value)}(selector, value)
    Write(field::Symbol, value) = Write(PropertySelector(field), value)
    Write(idx::Int, value) = Write(IdxSelector(idx), value)
    Write(subarray::UnitRange{Int}, value) = Write(SubArraySelector(subarray), value)
    Write(field1, fieldorsub2, value) = Write(field1, Write(fieldorsub2, value))
    Write(field1, field2, fieldorsub3, value) = Write(field1, Write(field2, Write(fieldorsub3, value)))
end

struct Transaction{TWrites}
    id::TransactionId
    identity::DistributedIdentities.DistIdId
    writes::TWrites
    initiator::Addr
    Transaction(me, writes) = new{typeof(writes)}(rand(TransactionId), distid(me), writes, addr(me))
end

function select(from, selector::PropertySelector)
    return getproperty(from, selector.propertyname)
end

function select(from, selector::IdxSelector)
    return getindex(from, selector.idx)
end

_set!(target, selector::PropertySelector, value) = setproperty!(target, selector.propertyname, value)

function _set!(target, selector::IdxSelector, value)
    if length(target) < selector.idx
        resize!(target, selector.idx)
    end
    target[selector.idx] = value
end

function apply!(target, write::Union{Write{PropertySelector}, Write{IdxSelector}})
    if write.value isa Write
        prop = select(target, write.selector)
        apply!(prop, write.value)
    else
        _set!(target, write.selector, write.value)
    end
end

function apply!(target, write::Write{SubArraySelector})
    if length(target) < write.selector.toidx
        resize!(target, write.selector.toidx)
    end
    copyto!(target, write.selector.fromidx, write.value, 1, length(write.value))
end

abstract type ConsistencyStyle end
struct Inconsistency <: ConsistencyStyle end

consistency_style(::Type) = Inconsistency

function commit!(me, write, service)
    commit!(consistency_style(typeof(me)), me, write, service)
end

end # module