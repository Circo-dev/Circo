module MultiTaskTest

using Test
using Circo, Circo.MultiTask

const TASK_COUNT = 100

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

mutable struct MultiTaskTester <: Actor{Any}
  server::Addr
  bgservice::Addr
  receivedResponses::Vector{ClientResp}
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
  me.receivedResponses = Vector{ClientResp}()

  for i=1:TASK_COUNT
    send(srv, me, me.server, ClientReq(i, me))
  end
end

Circo.onmessage(me::MultiTaskTester, msg::ClientResp, srv) = begin
  push!(me.receivedResponses, msg)

  if length(me.receivedResponses) == TASK_COUNT
    ingoodorder = true
    for i = 2:TASK_COUNT
      ingoodorder &= me.receivedResponses[i-1].data < me.receivedResponses[i].data
    end
    @test ingoodorder == true
  end
end

Circo.onmessage(me::SerializedServer, msg::ClientReq, srv) = begin
  srv.scheduler.msgqueue
  # NOTE Resp type
  response = request(srv, me, me.bgservice, Req(msg.data, me))
  @test response.data == msg.data

  send(srv, me, msg.respondto, ClientResp(response.data))
end

Circo.onmessage(me::BgService, req::Req, srv) = begin
  @async begin
    sleep(rand() / 100)
    send(srv, me, req.respondto, Resp(req.data, req.token))
  end
end

@testset "Multitask" begin
  tester = MultiTaskTester()
  ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [MultiTaskService])
  scheduler = Scheduler(ctx, [tester])
  # NOTE we need "remote = false" because remote's deafult value is true in this case 
  scheduler(; remote = false, exit=true)
  @info scheduler.msgqueue
  Circo.shutdown!(scheduler)
end

end # module
