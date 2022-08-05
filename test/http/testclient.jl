using Test
using Circo, Circo.Http
import Sockets
import Circo:onmessage, onspawn


const RESPONSE_BODY_MSG = "Message arrived. Processing succesfull by "
const REQUEST_BODY_MSG= "Test Message"

mutable struct HttpTestCaller <: Actor{Any}
    core::Any
    requestsent::Bool
    responsearrived::Bool
    reqtokensent::Token
    reqtokenarrived::Token
    orchestrator::Addr

    HttpTestCaller(core) = new(core)
end

mutable struct StartMsg 
    method
    body
    withkeywordparams::Bool
    url::AbstractString

    StartMsg(method, body, withkeywordparams) = new(method, body, withkeywordparams)
end

struct VerificationMsg
    responsebody
end

struct StartHttpTest <: CircoCore.AbstractMsg{Any}
    sender::CircoCore.Addr
    target::CircoCore.Addr
    body::StartMsg
end

function Circo.onspawn(me::HttpTestCaller, service)
    me.requestsent = false
    me.responsearrived = false
    me.reqtokensent = Token(UInt64(12))
    me.reqtokenarrived = Token(UInt64(0))
end

function Circo.onmessage(me::HttpTestCaller, msg::StartMsg, service)
    httpactor = getname(service, "httpclient")
    println("Prepare message to $(msg.url)")
    
    request = nothing
    if msg.withkeywordparams == true 
        keywordargs = ( retry = true
                , status_exception = true
                , readtimeout = 1
            )
        request = HttpRequest(;
            token = me.reqtokensent
            , respondto = addr(me)
            , method = msg.method
            , target = msg.url
            , headers = []
            , body = msg.body
            , keywordargs = keywordargs)
    else
        request = HttpRequest(
            token = me.reqtokensent
            , respondto = addr(me)
            , method = msg.method
            , target = msg.url
            , headers = []
            , body = msg.body)    
    end
    
    address = addr(me)
    @debug "Actor with address $address sending httpRequest with httpRequestToken :  $(request.token) message to $httpactor"
    me.requestsent = true
    send(service, me, httpactor, request)
end

function Circo.onmessage(me::HttpTestCaller, msg::HttpResponse, service)
    address = addr(me)
    responsebody = String(msg.body)
    @debug "HttpTestCaller with address $address got httpResponse message with token : $(msg.token)"
    @debug "Message : $(responsebody)"
    me.responsearrived = true
    me.reqtokenarrived = msg.token

    send(service, me, me.orchestrator, VerificationMsg(responsebody))
    die(service, me; exit=true)
end


mutable struct HttpRequestProcessor <: Actor{Any}
    requestProcessed::Bool
    core::Any

    HttpRequestProcessor(core) = new(false, core) 
end

# Register route to HttpRequestProcessor
function Circo.onspawn(me::HttpRequestProcessor, service)
    httpserveraddr = getname(service, "httpserver")
    @debug "Sending route information from $me to dispatcher : $(httpserveraddr)"

    route = PrefixRoute("/" , addr(me))
    send(service, me, httpserveraddr, route)
end


# Process incoming message 
function Circo.onmessage(me::HttpRequestProcessor, msg::HttpRequest, service)
    msgbody = String(msg.body)
    response = Http.HttpResponse(msg.token, 200, [], Vector{UInt8}("\"$(msgbody)\" " * RESPONSE_BODY_MSG * "$me"))

    me.requestProcessed = true
    @debug "Sending http response to $(msg.respondto) with token : $(msg.token) "
    send(service, me, msg.respondto, response)

    die(service, me; exit=true)
end

mutable struct TestOrchestrator <: Actor{Any}
    core::Any
    expectedresponsebody
    requestprocessedbyactor::Bool
    processoractor::HttpRequestProcessor
    httpcalleractor::HttpTestCaller

    TestOrchestrator(core, expectedbody) = new(core, expectedbody, true)
    TestOrchestrator(core, expectedbody, requestprocessed) = new(core, expectedbody, requestprocessed)
end

function Circo.onmessage(me::TestOrchestrator, msg::StartMsg, service)
    # code duplication. Copied from httpserver Circo.schedule_start 
    # TODO Get url from HttpServer plugin.
    listenport = 8080 + port(postcode(service.scheduler)) - CircoCore.PORT_RANGE[1]
    ipaddr = Sockets.IPv4(0) 
    url = "http://$(ipaddr):$(listenport)"

    msg.url = url
    send(service, me, me.httpcalleractor, msg)
end

#HttpTestCaller finished, start verifying
function Circo.onmessage(me::TestOrchestrator, msg::VerificationMsg, service)

    @test me.httpcalleractor.requestsent == true
    @test me.httpcalleractor.responsearrived == true
    @test me.httpcalleractor.reqtokensent == me.httpcalleractor.reqtokenarrived
    @test me.processoractor.requestProcessed == me.requestprocessedbyactor
    @test startswith(msg.responsebody, me.expectedresponsebody)  

    die(service, me; exit=true)

    Circo.shutdown!(service.scheduler)
end

@testset "Http modul tests" begin
    @testset "Http client and server test" begin
        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [HttpServer, HttpClient])

        caller = HttpTestCaller(emptycore(ctx))
        processor = HttpRequestProcessor(emptycore(ctx))
        orchestrator = TestOrchestrator(emptycore(ctx), "\"$REQUEST_BODY_MSG\" $RESPONSE_BODY_MSG")

        scheduler = Scheduler(ctx, [orchestrator, processor, caller])
        scheduler(;remote=false) # to spawn the zygote

        orchestrator.processoractor = processor
        orchestrator.httpcalleractor = caller
        caller.orchestrator = orchestrator

        msg = StartMsg("GET", REQUEST_BODY_MSG, false)

        scheduler([
            StartHttpTest(orchestrator, orchestrator, msg)
            ] ;remote = true)  # with remote,exit flags the scheduler won't stop.
    end

    @testset "request_bigger_than_allowed" begin
        maxsizeofrequest = get(ENV, "HTTP_MAX_REQUEST_SIZE", nothing)
        try
            ENV["HTTP_MAX_REQUEST_SIZE"] = 10
            ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [HttpServer, HttpClient])

            caller = HttpTestCaller(emptycore(ctx))
            processor = HttpRequestProcessor(emptycore(ctx))
            orchestrator = TestOrchestrator(emptycore(ctx), "Payload size is too big! Accepted maximum", false)

            scheduler = Scheduler(ctx, [orchestrator, processor,caller])
            scheduler(;remote=false) # to spawn the zygote
            orchestrator.processoractor = processor
            orchestrator.httpcalleractor = caller
            caller.orchestrator = orchestrator

            msg = StartMsg("GET", REQUEST_BODY_MSG, false)
            
            scheduler([
                StartHttpTest(orchestrator, orchestrator, msg)
                ] ;remote = true)  # with remote,exit flags the scheduler won't stop. 
        finally
            if maxsizeofrequest === nothing
                delete!(ENV, "HTTP_MAX_REQUEST_SIZE")
            else 
                ENV["HTTP_MAX_REQUEST_SIZE"] = maxsizeofrequest
            end
        end
    end

    @testset "Http client and server test with keywordargs" begin
        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [HttpServer, HttpClient])

        caller = HttpTestCaller(emptycore(ctx))
        processor = HttpRequestProcessor(emptycore(ctx))
        orchestrator = TestOrchestrator(emptycore(ctx), "\"$REQUEST_BODY_MSG\" $RESPONSE_BODY_MSG")

        scheduler = Scheduler(ctx, [orchestrator, processor,caller])
        scheduler(;remote=false) # to spawn the zygote
        orchestrator.processoractor = processor
        orchestrator.httpcalleractor = caller
        caller.orchestrator = orchestrator

        msg = StartMsg("GET", REQUEST_BODY_MSG, true)

        scheduler([
            StartHttpTest(orchestrator, orchestrator, msg)
            ] ;remote = true)  # with remote,exit flags the scheduler won't stop.   
    end
end
