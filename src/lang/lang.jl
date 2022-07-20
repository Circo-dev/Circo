
function actorize(declaration)
    @assert declaration.head == :struct

    declaration.args[1] = true # make it mutable

    if declaration.args[2] isa Symbol # If no supertype is given
        declaration.args[2] = :($(declaration.args[2]) <: Actor{Any})  # Make it an Actor
        push!(declaration.args[3].args, :core) # Add the "core" field to the struct
    end

    return declaration
end

macro actor(declaration)
    return actorize(declaration)
end

macro onspawn(metype, body)
    @assert metype isa Symbol
    return quote
        Circo.onspawn(me::$(metype), service) = begin
            $(body)
        end
    end |> esc
end

macro onmessage(declaration, body)
    @assert declaration.head == :call && declaration.args[1] == :(=>) "Use the syntax @msg MsgType => ActorType begin ... end"
    metype = declaration.args[3]
    msgtype = declaration.args[2]
    return quote
        Circo.onmessage(me::$(metype), msg::$(msgtype), service) = begin
            $(body)
        end
    end |> esc
end

macro send(expr)
    @assert expr.head == :call && expr.args[1] == :(=>)
    msg = expr.args[2]
    target = expr.args[3]
    return quote
        send(service, me, $(target), $(msg))
    end |> esc
end

macro spawn(expr)
    return quote
        spawn(service, $(expr))
    end |> esc
end

macro become(expr)
    return quote
        become(service, me, $(expr))
    end |> esc
end

macro die()
    return quote
        die(service, me)
    end |> esc
end

macro identity(declaration)
    actorized = actorize(declaration)
    push!(declaration.args[3].args, Circo.DistributedIdentities.distid_field())
    return declaration
end

macro @response(requesttype, responsetype)
    return quote
        Circo.MultiTask.responsetype(::Type{$(requesttype)}) = $(responsetype)
    end |> esc
end
