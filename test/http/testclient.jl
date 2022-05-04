using Test
using Circo, Circo.Http
import Circo:onmessage, onspawn

mutable struct HttpTestCaller <: Actor{Any}
    core::Any
    requestsent::Bool
    responsearrived::Bool
    reqidsent::Integer
    reqidarrived::Integer

    HttpTestCaller(core) = new(core)
end

struct StartMsg end

struct StartHttpTest <: CircoCore.AbstractMsg{Any}
    sender::CircoCore.Addr
    target::CircoCore.Addr
    body::VmiMas
end

function Circo.onspawn(me::HttpTestCaller, service)
    me.requestsent = false
    me.responsearrived = false
    me.reqidsent = 12
    me.reqidarrived = 0
end

#TODO This can be incorporated into the HttpTestCaller's onspawn after the problem with zygote handling solved ( Problem: zygote starts before the plugin's actors can be registered )
function Circo.onmessage(me::HttpTestCaller, ::StartMsg, service)
    httpactor = getname(service, "httpclient")
    request = HttpRequest(me.reqidsent, addr(me), "GET", "http://localhost:8080/test")
    
    address = addr(me)
    println("Actor with address $address sending httpRequest with httpRequestId :  $(request.id) message to $httpactor")
    me.requestsent = true
    send(service, me, httpactor, request)
end

function Circo.onmessage(me::HttpTestCaller, msg::HttpResponse, service)
    address = addr(me)
    println("Actor with address $address got httpResponse message with httpRequestId : $(msg.reqid)")
    me.responsearrived = true
    me.reqidarrived = msg.reqid

    println(service.scheduler.msgqueue)
    die(service, me)
end

@testset "Httpclient" begin
    ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [HttpClient])
    tester = HttpTestCaller(emptycore(ctx))

    scheduler = Scheduler(ctx, [tester])
    scheduler([StartHttpTest(tester, tester, VmiMas())] ;exit=true)
    
    Circo.shutdown!(scheduler)
    println("After circo.shutdown! $(scheduler.msgqueue)")

    @test tester.requestsent == true
    @test tester.responsearrived == true
    @test tester.reqidsent == tester.reqidarrived
end