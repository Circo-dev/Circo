# SPDX-License-Identifier: MPL-2.0

abstract type HttpClient <: Plugin end
Plugins.symbol(plugin::HttpClient) = :httpclient

mutable struct HttpClientActor <: Actor{Any} 
    core::Any
    HttpClientActor() = new()
end

mutable struct HttpClientImpl <: HttpClient
    helper::HttpClientActor
    HttpClientImpl(;options...) = new()
end

function Circo.schedule_start(http::HttpClientImpl, scheduler)
    http.helper = HttpClientActor()
    spawn(scheduler.service, http.helper)
    registername(scheduler.service, "httpclient", http.helper)

    address = addr(http.helper)
    println("HttpClientActor.addr : $address")
end

function Circo.onmessage(me::HttpClientActor, msg::HttpRequest, service)
    println("Actor with address : $(addr(me)) got message!")
    response = HTTP.request(msg.raw.method, msg.raw.target, msg.raw.headers, msg.raw.body; connection_limit=30)
    println(response.status)
    address = msg.respondto
    println("Sending HttpResponse message to $address")
    
    ownresponse = HttpResponse(msg.id, response.status, response.headers, response.body)
    send(service.scheduler, address , ownresponse)
end

function Circo.onmessage(me::HttpClientActor, msg::HttpResponse, service)
    address = addr(me)
    println("Response arrived! $address")
    println(msg.status)

    println("Get registered Actor named : 'httpclient'")
    pluginActor = getname(service, "httpclient")
    println("Plugin actor's address $pluginActor")
end