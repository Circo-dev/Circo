# SPDX-License-Identifier: MPL-2.0
module Http

export HttpRequest, HttpResponse, PrefixRoute, HttpServer, HttpClient

using ..Circo
using Plugins
using HTTP
import HTTP, Sockets
using Logging

HttpReqId = UInt64
struct HttpRequest
    id::HttpReqId
    respondto::Addr
    raw::HTTP.Messages.Request

    HttpRequest(id, respondto, request::HTTP.Messages.Request) = new(id, respondto, request)
    HttpRequest(id, respondto, method, url) = new(id, respondto, HTTP.Messages.Request(method, url) )
    HttpRequest(id, respondto, method, url, headers) = new(id, respondto, HTTP.Messages.Request(method, url, headers))
    HttpRequest(id, respondto, method, url, headers, body) = new(id, respondto, HTTP.Messages.Request(method, url, headers, body))
end

struct HttpResponse
    reqid::HttpReqId
    status::Int16
    headers::Vector{Pair{String,String}}
    body::Vector{UInt8}
end

include("httpclient.jl")
include("httpserver.jl")

__init__() = begin 
    Plugins.register(HttpServerImpl)
    Plugins.register(HttpClientImpl)
end

end #module