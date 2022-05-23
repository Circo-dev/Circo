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
    target::String
    method::String
    headers::Vector{Pair{String,String}}
    body
    keywordargs::NamedTuple

    HttpRequest(id, respondto, method, url) = new(id, respondto, url, method )
    HttpRequest(id, respondto, method, url, headers) = new(id, respondto, url, method, headers)
    HttpRequest(id, respondto, method, url, headers, body; keywordarg = NamedTuple()) = new(id, respondto, url, method, headers, body, keywordarg)
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