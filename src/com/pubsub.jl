# Ref cheatsheet
# Refs are relative to the component receiving a Sub or FindRef command
# They are evaluated incrementally (splitted at slashes)
# Refs may optionally describe a topic to filter events
#
# ../name1/                 sibling with name=name1 (go to parent then select by name), no topic specified
# [exchange1]/@btcusdt      btcusdt topic of the component with address stored (as string) in the exchange1 attr
# |/                        previous sibling

struct Sub <: Request
    subscriber::Addr
    ref::String
    eventtype::Type
    token::Token
end

"""
    sub(srv, me, ref::String, eventtype::Type)

    Subscribe to an event on the component referenced by ref.
    return the token of the sub request.
    TODO send back Subbed
"""
function sub(srv, me, ref::String, eventtype::Type)
    token = Token()
    send(srv, me, addr(me), Sub(me, ref, eventtype, token))
    return token
end

"""
    findref(srv, me, ref::String)

    Find the component referenced by ref.
    The result will be sent back as RefFound or RefNotFound
    Return the token of the request.
"""
function evalref(srv, me, ref::String)
    token = Token()
    send(srv, me, addr(me), FindRef(me, ref, token))
    return token
end

"""
    FindRef(respondto::Addr, ref::String)

    Find the component referenced by ref and send back a RefFound or RefNotFound.
"""
struct FindRef
    respondto::Addr
    ref::String
    token::Token
end

struct RefFound
    token::Token
    addr::Addr
end

struct RefNotFound
    token::Token
    remainingref::Union{String, Nothing}
    sender::Addr
end

Circo.onmessage(me::Actor, msg::FindRef, srv) = begin
    foundaddr, remainingref = evalref(me, msg.ref)
    if isnothing(foundaddr)
        if remainingref == "" || (!isnothing(remainingref) && startswith(remainingref, "@")) # TODO check topic validity
            return send(srv, me, me, RefFound(msg.token, addr(me)))
        else
            return send(srv, me, me, RefNotFound(msg.token, remainingref, addr(me)))
        end 
    else
        send(srv, me, foundaddr, FindRef(msg.respondto, remainingref, msg.token))
    end
end


Circo.onmessage(me::Actor, msg::Sub, srv) = begin
    foundaddr, remainingref = evalref(me, msg.ref)
    if isnothing(foundaddr)
        if remainingref == ""
            return send(srv, me, me, Subscribe(msg.eventtype, msg.subscriber)) # No topic
        elseif !isnothing(remainingref) && startswith(remainingref, "@")
            return send(srv, me, me, Subscribe(msg.eventtype, msg.subscriber, remainingref[2:end])) # topic specified TODO check validity
        else
            return send(srv, me, me, RefNotFound(msg.token, msg.subscriber, addr(me)), remainingref)
        end 
    else
        send(srv, me, foundaddr, Sub(msg.subscriber, remainingref, msg.eventtype, msg.token))
    end
end

# return (nextaddr, remainingref) where nextaddr is the address to forward remainingref.
# nextaddr will be nothing if me is the target of this ref (no slash in it)
# In that case remainingref may contain the topic name (starting with @) or be the empty string if no topic specified
# return (nothing, nothing) if ref cannot be understood
evalref(me::Actor, ref::String) = begin
    slash = findfirst("/", ref)
    if isnothing(slash)
        if ref == "" || startswith(ref, "@")
            return (nothing, ref) # it's me
        else
            virtidx = length(ref) + 1
            slash = virtidx:virtidx
        end
    end
    currentpart = first(ref, slash.start - 1)
    evaled = evalrefpart(me, currentpart)
    if isnothing(evaled)
        @warn "Could not eval '$(currentpart)' in $(ref)"
        return (nothing, nothing)
    end
    remainingref = ref[slash.stop+1:end]
    return (evaled, remainingref)
end

function evalrefpart(me, refpart::String)
    if refpart == ".."
        return Addr(me.attrs["parent"])
    elseif refpart == "|"
        return Addr(me.attrs["prev"])
    elseif startswith(refpart, "[")
        return Addr(me.attrs[refpart[2:end-1]])
    else
        idx = findfirst(child -> get(child.attrs, "name", nothing) == refpart, me.children)
        return isnothing(idx) ? nothing : me.children[idx].addr
    end
end
