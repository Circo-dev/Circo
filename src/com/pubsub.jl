
struct Sub <: Request
    subscriber::Addr
    ref::String
    eventtype::Type
    token::Token
end

gensubid() = rand(UInt64)

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
function findref(srv, me, ref::String)
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
    remainingref::String
    sender::Addr
end

Circo.onmessage(me::Actor, msg::FindRef, srv) = begin
    foundaddr, remainingref = findref(me, msg.ref)
    if isnothing(foundaddr)
        if remainingref == ""
            return send(srv, me, me, RefFound(msg.token, addr(me)))
        else
            return send(srv, me, me, RefNotFound(msg.token, remainingref, addr(me)))
        end 
    else
        send(srv, me, foundaddr, FindRef(msg.respondto, remainingref, msg.token))
    end
end


Circo.onmessage(me::Actor, msg::Sub, srv) = begin
    foundaddr, remainingref = findref(me, msg.ref)
    if isnothing(foundaddr)
        if remainingref == ""
            return send(srv, me, me, Subscribe{msg.eventtype}(msg.subscriber))
        else
            return send(srv, me, me, RefNotFound(msg.token, msg.subscriber, addr(me)), remainingref)
        end 
    else
        send(srv, me, foundaddr, Sub(msg.subscriber, remainingref, msg.eventtype, msg.token))
    end
end

findref(me::Actor, ref::String) = begin
    slash = findfirst("/", ref)
    if isnothing(slash)
        if ref == ""
            return (nothing, "") # it's me
        else
            virtidx = length(ref) + 1
            slash = virtidx:virtidx
        end
    end
    currentpart = first(ref, slash.start - 1)
    evaled = evalrefpart(me, currentpart)
    if isnothing(evaled)
        @warn "Could not eval '$(currentpart)' in $(ref)"
        return (nothing, ref)
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
