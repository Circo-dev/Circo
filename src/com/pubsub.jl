
struct Sub
    subscriber::Addr
    ref::String
    eventtype::Type
end

"""
    sub(srv, me, ref::String, eventtype::Type)

    Subscribe to an event on the component referenced by ref.
"""
function sub(srv, me, ref::String, eventtype::Type)
    send(srv, me, addr(me), Sub(me, ref, eventtype))
end

Circo.onmessage(me::Actor, msg::Sub, srv) = begin
    slash = findfirst("/", msg.ref)
    if isnothing(slash)
        if msg.ref == ""
            return send(srv, me, me, Subscribe{msg.eventtype}(msg.subscriber))
        else
            virtidx = length(msg.ref) + 1
            slash = virtidx:virtidx
        end
    end
    currentpart = first(msg.ref, slash.start - 1)
    evaled = evalrefpart(me, currentpart)
    if isnothing(evaled)
        @warn "Could not eval '$(currentpart)' in $(msg.eventtype)@$(msg.ref)"
        return
    end
    nextref = msg.ref[slash.stop+1:end]
    send(srv, me, evaled, Sub(msg.subscriber, nextref, msg.eventtype))
end

function evalrefpart(me, refpart::String)
    if refpart == ".."
        return Addr(me.attrs["parent"])
    elseif startswith(refpart, "[")
        return @show Addr(me.attrs[refpart[2:end-1]])
    else
        idx = findfirst(child -> get(child.attrs, "name", nothing) == refpart, me.children)
        return isnothing(idx) ? nothing : me.children[idx].addr
    end
end
