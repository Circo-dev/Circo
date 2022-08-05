module MultiTaskTest

using Test
using Circo, Circo.MultiTask

const TASK_COUNT = 13

struct Req <: Request
    data
    respondto::Addr
    token::Token
    Req(data, respondto) = new(data, respondto, Token())
end

struct Resp <: Response
    data
    token::Token
end

Circo.MultiTask.responsetype(::Type{Req}) = Resp
# @resp Req => Resp

struct ClientReq
    data
    respondto::Addr
end

struct ClientResp
    data
end


mutable struct MultiTaskClient <: Actor{Any}
    orchestrator::Addr
    server::Addr
    bgservice::Addr
    receivedResponses::Vector{ClientResp}
    core

    MultiTaskClient(addr) = new(addr)
end

mutable struct SerializedServer <: Actor{Any}
    bgservice::Addr
    core
    SerializedServer(bgservice::Addr) = new(bgservice)
end

mutable struct BgService <: Actor{Any}
    core
    BgService() = new()
end

struct StartMsg end
struct ValidationOK end
struct Die end

mutable struct TestOrchestrator <: Actor{Any}
    numberofclient::Integer
    multitaskclients::AbstractArray{Addr}
    numberofsuccesfulvalidation
    core

    TestOrchestrator(numberofclient) = new(numberofclient, Vector{Addr}(), 0)
end

Circo.onmessage(me::TestOrchestrator, ::OnSpawn, srv) = begin
    for i = 1:me.numberofclient
        multitaskclient = spawn(srv, MultiTaskClient(addr(me)))
        insert!(me.multitaskclients, i, multitaskclient)

        send(srv, me, multitaskclient, StartMsg())
    end
end

Circo.onmessage(me::TestOrchestrator, msg::ValidationOK, srv) = begin
    me.numberofsuccesfulvalidation += 1
    if me.numberofsuccesfulvalidation == me.numberofclient
        @info "All clients validated"
        die(srv, me; exit = true)
    end
end

Circo.onmessage(me::MultiTaskClient, ::OnSpawn, srv) = begin
    me.bgservice = spawn(srv, BgService())
    me.server = spawn(srv, SerializedServer(me.bgservice))
    me.receivedResponses = Vector{ClientResp}()
end

Circo.onmessage(me::MultiTaskClient, msg::StartMsg, srv) = begin
    @debug "MultiTaskClient start"
    for i = 1:TASK_COUNT
        send(srv, me, me.server, ClientReq(i, me))
    end
end

Circo.onmessage(me::MultiTaskClient, msg::ClientResp, srv) = begin
    @debug "ClientResp arrived to MultiTaskClientnek" addr(me) msg
    push!(me.receivedResponses, msg)

    if length(me.receivedResponses) == TASK_COUNT
        ingoodorder = true
        for i = 2:TASK_COUNT
            ingoodorder &= me.receivedResponses[i-1].data < me.receivedResponses[i].data
        end
        @test ingoodorder == true

        send(srv, me, me.orchestrator, ValidationOK())
        send(srv, me, me.server, Die())
        die(srv, me; exit = true)
    end
end

Circo.onmessage(me::SerializedServer, msg::ClientReq, srv) = begin
    srv.scheduler.msgqueue
    requestObject = Req(msg.data, me)
    @debug "SerializedServer $(addr(me)) sending request" requestObject me.bgservice
    response = awaitresponse(srv, me, me.bgservice, requestObject)
    @debug "SerializedServer $(addr(me)) got response" requestObject me.bgservice response
    @test response.data == msg.data

    send(srv, me, msg.respondto, ClientResp(response.data))
end

Circo.onmessage(me::BgService, req::Req, srv) = begin
    @debug "sleep + send BgService $(addr(me))"

    @async begin
        sleep(rand() / 100)
        send(srv, me, req.respondto, Resp(req.data, req.token))
        @debug "BgService send $(addr(me))" req
    end
end

Circo.onmessage(me::SerializedServer, msg::Die, srv) = begin
    send(srv, me, me.bgservice, Die())
    die(srv, me; exit = true)
end

Circo.onmessage(me::BgService, msg::Die, srv) = begin
    die(srv, me; exit = true)
end

@testset "MultiTask" begin
    @testset "One MultiTaskClient and SerializedServer" begin
        orchestrator = TestOrchestrator(1)
        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [MultiTaskService])
        scheduler = Scheduler(ctx, [orchestrator])
        scheduler(;)
        Circo.shutdown!(scheduler)
    end

    @testset "Multiple MultiTaskClients and SerializedServers" begin
        orchestrator = TestOrchestrator(51)
        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [MultiTaskService])
        scheduler = Scheduler(ctx, [orchestrator])
        scheduler(;)
        Circo.shutdown!(scheduler)
    end
end

end # module
