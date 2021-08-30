module LeadGroup

export LeadGroupPeer, @leadgroup_field

using ....Circo
using CircoCore, Circo.DistributedIdentities, Circo.Transactions

function onelected(me, service) end
function onresign(me, newleader, service) end

abstract type LeadGroupPeer{TCore} <: Actor{TCore} end

mutable struct LeadGroupField
    leader::Union{Addr, Nothing}
    LeadGroupField() = new(nothing)
end

macro leadgroup_field()
    return quote
        leadgroup::Circo.LeadGroup.LeadGroupField
    end |> esc
end

DistributedIdentities.identity_style(::Type{<:LeadGroupPeer}) = DenseDistributedIdentity()
Transactions.consistency_style(::Type{<:LeadGroupPeer}) = Inconsistency() # TODO implement multi-stage commit

_iamleader(me::LeadGroupPeer) = !isnothing(me.leadgroup.leader) && box(me.leadgroup.leader) == box(me)

DistributedIdentities.initialized(me::LeadGroupPeer, service) = begin
    me.leadgroup = LeadGroupField()
    _check_elect(me, service)
end

DistributedIdentities.peer_joined(me::LeadGroupPeer, peer::Addr, service) = begin
    _check_elect(me, service)
end

DistributedIdentities.peer_leaved(me::LeadGroupPeer, peer::Addr, service) = begin
    _check_elect(me, service)    
end

struct IAmTheLeader
    leader::Addr
end

function _check_elect(me::LeadGroupPeer, service)
    allpeers = DistributedIdentities.addrs(me)
    if length(allpeers) <= 1 return false end
    
    nextleader = allpeers[argmax(box.(allpeers))]
    
    if nextleader == me.leadgroup.leader return false end
    
    if _iamleader(me) && nextleader != addr(me)
        onresign(me, nextleader, service)
    elseif !_iamleader(me) && nextleader == addr(me)
        onelected(me, service)
    end
    
    me.leadgroup.leader = nextleader
    return true
end

end # module
