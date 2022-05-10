using Test
using Circo, Circo.Http
import Sockets
import Circo:onmessage, onspawn

mutable struct HttpTestCaller <: Actor{Any}
    core::Any
    requestsent::Bool
    responsearrived::Bool
    reqidsent::Integer
    reqidarrived::Integer
    orchestrator::Addr

    HttpTestCaller(core) = new(core)
end

struct StartMsg 
    url::AbstractString

    StartMsg() = new("")
    StartMsg(url) = new(url)
end

struct VerificationMsg
end

struct StartHttpTest <: CircoCore.AbstractMsg{Any}
    sender::CircoCore.Addr
    target::CircoCore.Addr
    body::StartMsg
end

function Circo.onspawn(me::HttpTestCaller, service)
    me.requestsent = false
    me.responsearrived = false
    me.reqidsent = 12
    me.reqidarrived = 0
end

function Circo.onmessage(me::HttpTestCaller, msg::StartMsg, service)
    httpactor = getname(service, "httpclient")
    println("Prepare message to $(msg.url)")
    request = HttpRequest(me.reqidsent, addr(me), "GET", msg.url, [], "Test Message")
    
    address = addr(me)
    println("Actor with address $address sending httpRequest with httpRequestId :  $(request.id) message to $httpactor")
    me.requestsent = true
    send(service, me, httpactor, request)
end

function Circo.onmessage(me::HttpTestCaller, msg::HttpResponse, service)
    address = addr(me)
    println("HttpTestCaller with address $address got httpResponse message with httpRequestId : $(msg.reqid)")
    me.responsearrived = true
    me.reqidarrived = msg.reqid

    send(service.scheduler, me.orchestrator, VerificationMsg())
    println("HttpTestCaller at $me goint to die")
    die(service, me)
end


mutable struct HttpRequestProcessor <: Actor{Any}
    requestProcessed::Bool
    core::Any

    HttpRequestProcessor(core) = new(false, core) 
end

# Register route to HttpRequestProcessor
function Circo.onspawn(me::HttpRequestProcessor, service)
    httpserveraddr = getname(service, "httpserver")
    println("Sending route information from $me to dispatcher : $(httpserveraddr)")

    route = PrefixRoute("/" , addr(me))
    send(service.scheduler, httpserveraddr, route)
end


# Process incoming message 
function Circo.onmessage(me::HttpRequestProcessor, msg::HttpRequest, service)
    println("Circo.onmessage(me::HttpRequestProcessor, msg::HttpRequest, service)")


    #Ha a 200 -> "200" -at írok akkor Addr-re akarja konvertálni ...
    stateCode = 200
    response = Http.HttpResponse(msg.id, stateCode, [], Vector{UInt8}("Message $(msg.raw.body) arrived. Processing succesfull by $me"))

    me.requestProcessed = true
    println("Sending http response to message with reqid : $(msg.id) ")
    send(service.scheduler, msg.respondto, response)

    println("HttpRequestProcessor at $me goint to die")
    die(service, me)
end

mutable struct TestOrchestrator <: Actor{Any}
    core::Any
    processoractor::HttpRequestProcessor
    httpcalleractor::HttpTestCaller

    TestOrchestrator(core) = new(core)
end

function Circo.onmessage(me::TestOrchestrator, ::StartMsg, service)
    # code duplication. Copied from httpserver Circo.schedule_start 
    # TODO Get url from HttpServer plugin.
    listenport = 8080 + port(postcode(service.scheduler)) - CircoCore.PORT_RANGE[1]
    ipaddr = Sockets.IPv4(0) 
    url = "http://$(ipaddr):$(listenport)"

    println("Sending StartMsg to HttpTestCaller")
    send(service.scheduler, me.httpcalleractor, StartMsg(url))
end

#HttpTestCaller finished, start verifying
function Circo.onmessage(me::TestOrchestrator, ::VerificationMsg, service)
    println("Verification starts")

    @test me.httpcalleractor.requestsent == true
    @test me.httpcalleractor.responsearrived == true
    @test me.httpcalleractor.reqidsent == me.httpcalleractor.reqidarrived
    @test me.processoractor.requestProcessed == true

    println("TestOrchestrator at $me goint to die")
    die(service, me)

    println("Call Circo.shutdown on scheduler")
    Circo.shutdown!(service.scheduler)
end

@testset "Httpclientserver" begin
    println("Httpclientserver test starts")
    ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [HttpServer, HttpClient])

    caller = HttpTestCaller(emptycore(ctx))
    processor = HttpRequestProcessor(emptycore(ctx))
    orchestrator = TestOrchestrator(emptycore(ctx))

    scheduler = Scheduler(ctx, [orchestrator, processor,caller])
    scheduler(;remote=false, exit=true) # to spawn the zygote
    orchestrator.processoractor = processor
    orchestrator.httpcalleractor = caller
    caller.orchestrator = orchestrator

    scheduler([
        StartHttpTest(orchestrator, orchestrator, StartMsg())
        ] ;remote = true, exit=true)  # with remote,exit flags the scheduler won't stop.   

    println("Httpclientserver test ends")
end