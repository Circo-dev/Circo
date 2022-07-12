module MultiTaskTest

using Test
using Circo, Circo.MultiTask

const TASK_COUNT = 5

struct Req <: Request
  data
  respondto
  token::Token
  Req(data, respondto) = new(data, respondto, Token())
end

struct Resp <: Response
  data
  token::Token
end

Circo.MultiTask.responsetype(::Type{Req}) = Resp

struct ClientReq
  data
  respondto
end

struct ClientResp
  data
end

mutable struct MultiTaskTester <: Actor{Any}
  server::Addr
  bgservice::Addr
  core
  MultiTaskTester() = new()
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

Circo.onspawn(me::MultiTaskTester, srv) = begin
  me.bgservice = spawn(srv, BgService())
  me.server = spawn(srv, SerializedServer(me.bgservice))
  for i=1:TASK_COUNT
    send(srv, me, me.server, ClientReq(i, me))
  end
end

Circo.onmessage(me::SerializedServer, msg::ClientReq, srv) = begin
  @show srv.scheduler.msgqueue
  response = request(srv, me, me.bgservice, Req(msg.data, me))
  @test response.data == msg.data
end

Circo.onmessage(me::BgService, req::Req, srv) = begin
  #if rand() < 0.99
  #  send(srv, me, me, req)
  #else
    send(srv, me, req.respondto, Resp(req.data, req.token))
  #end
end

@testset "Multitask" begin
  tester = MultiTaskTester()
  ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [MultiTaskService])
  scheduler = Scheduler(ctx, [tester])
  scheduler(;exit=true)
  @info scheduler.msgqueue
  Circo.shutdown!(scheduler)
end

end # module