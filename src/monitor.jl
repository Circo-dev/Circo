# SPDX-License-Identifier: MPL-2.0
module Monitor

export MonitorService, registermsg, JS

using ..Circo
using Plugins
using TypeParsers

struct ActorInfo{TExtra}
    typename::String
    box::ActorId
    x::Float32
    y::Float32
    z::Float32
    extra::TExtra
    ActorInfo(actor::Actor, extras) = new{typeof(extras)}(string(typeof(actor)), box(actor.core.addr),
     pos(actor).x, pos(actor).y, pos(actor).z, extras)
end

struct NoExtra
    a::Nothing # MsgPack.jl fails for en empty struct (at least when the default is StructType)
    NoExtra() = new(nothing)
end
noextra = NoExtra()

Circo.monitorextra(actor::Actor) = noextra

monitorinfo(actor::Actor) = ActorInfo(actor, Circo.monitorextra(actor))

struct JS
    src::String
end

Circo.monitorprojection(::Type{<: Actor}) = JS("{
    geometry: new THREE.BoxBufferGeometry(20, 20, 20),
    scale: { x: 1, y: 1, z: 1 },
    rotation: { x: 0, y: 0, z: 0 }
}")

Circo.monitorprojection(::Type{<:CircoCore.Registry.RegistryHelper}) = JS("projections.nonimportant") # TODO: trait or type for nonimportant
Circo.monitorprojection(::Type{<:CircoCore.EventDispatcher}) = JS("projections.nonimportant")

struct ActorListRequest <: Request
    respondto::Addr
    token::Token
end

struct ActorListResponse <: Response
    actors::Vector{ActorInfo}
    token::Token
end

struct ActorInterfaceRequest <: Request
    respondto::Addr
    box::ActorId
    token::Token
end

struct MessageType
    typename::String
    registrator_snippet::JS
end

MessageType(T::Type, params::NamedTuple=NamedTuple();ui = false) = MessageType(string(T), generate_registrator(T, params; ui=ui))

function generate_registrator(T::Type, params::NamedTuple;ui=false)
    typename = string(T)
    lastdot = findlast(".", typename)
    classname = isnothing(lastdot) ? typename : typename[lastdot[1] + 1:end]
    return JS(
"""
class $classname {
    constructor() {
        this.a=42
    }
}
registerMsg("$typename", $classname, { ui: $ui })
""")
end

const msgtype_registry = Dict()

function registermsg(msgtype::Type, params::NamedTuple = NamedTuple();ui=false)
    reg =  MessageType(msgtype, params; ui = ui)
    msgtype_registry[msgtype] = reg
    return reg
end

function getregisteredmsg(msgtype::Type)
    retval = get(msgtype_registry, msgtype, nothing)
    if isnothing(retval)
        retval = registermsg(msgtype)
    end
    return retval
end

struct ActorInterfaceResponse <: Response
    box::ActorId
    messagetypes::Vector{MessageType}
    token::Token
end

struct MonitorProjectionRequest <: Request
    respondto::Addr
    typename::String
    token::Token
end

struct MonitorProjectionResponse <: Response
    projection::JS
    token::Token
end

mutable struct MonitorActor{TMonitor, TCore} <: Actor{TCore}
    monitor::TMonitor
    core::TCore
end

Circo.monitorextra(actor::MonitorActor)= (
    actorcount = UInt32(actor.monitor.scheduler.actorcount),
    queuelength = UInt32(length(actor.monitor.scheduler.msgqueue))
    )

Circo.monitorprojection(::Type{<:MonitorActor}) = JS("
{
    geometry: new THREE.BoxBufferGeometry(15, 15, 15),
    /*scale: me => {
        const plussize = me.extra.actorcount * 0.00002
        // Works only for origo-centered setups:
        return { x: 1 + plussize * Math.abs(me.y + me.z), y: 1 + plussize * Math.abs(me.x + me.z), z: 1 + plussize * Math.abs(me.x + me.y)}
    },*/
    color: 0x4063d8
}")

"""
    Throw

Message that throws an error from the monitoring actor
"""
struct Throw a::UInt8 end
registermsg(Throw; ui = true)

function Circo.onmessage(me::MonitorActor, ::Throw, service)
    error("Exception forced from $me")
end

abstract type MonitorService <: Plugin end
mutable struct MonitorServiceImpl <: MonitorService
    actor::MonitorActor
    scheduler::CircoCore.AbstractScheduler
    MonitorServiceImpl(;options...) = new()
end
Plugins.symbol(::MonitorService) = :monitor
__init__() = Plugins.register(MonitorServiceImpl)

function Plugins.setup!(monitor::MonitorServiceImpl, scheduler)
    monitor.actor = MonitorActor(monitor, emptycore(scheduler.service))
    monitor.scheduler = scheduler
    schedule!(scheduler, monitor.actor)
    registername(scheduler.service, "monitor", monitor.actor)
end

function _updatepos(me::MonitorActor)
    me.core.pos = me.monitor.scheduler.pos
end

function Circo.onmessage(me::MonitorActor, request::ActorListRequest, service)
    _updatepos(me)
    result = [monitorinfo(actor) for actor in values(me.monitor.scheduler.actorcache)]
    send(service, me, request.respondto, ActorListResponse(result, request.token))
end

function Circo.onmessage(me::MonitorActor, request::MonitorProjectionRequest, service)
    projection = Circo.monitorprojection(parsetype(request.typename))
    @debug "monitorprojection for $(request.typename): $projection"
    send(service, me, request.respondto, MonitorProjectionResponse(projection, request.token))
end

# Retrieves the message type from an onmessage method signature
extract_messagetype(::Type{Tuple{A,B,C,D}}) where {D, C, B, A} = C

function Circo.onmessage(me::MonitorActor, request::ActorInterfaceRequest, service)
    actor = getactorbyid(me.monitor.scheduler, request.box)
    if isnothing(actor)
        return nothing # TODO a general notfound response
    end
    result = Vector{MessageType}()
    for m in methods(Circo.onmessage, [typeof(actor), Any, Any])
        if typeof(m.sig) === DataType # TODO handle UnionAll message types
            type = extract_messagetype(m.sig)
            if type != Any
                push!(result, getregisteredmsg(type))
            end
        end
    end
    send(service, me, request.respondto, ActorInterfaceResponse(request.box, result, request.token))
end

end # module