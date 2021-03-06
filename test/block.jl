using Test
using Circo, Circo.Blocking
import Circo:onmessage, onspawn

mutable struct Blocker <: Actor{Any}
    tester::Addr
    val
    core
    Blocker(addr) = new(addr, nothing)
end

@enum TestState start block_sent blocked unblocked

mutable struct BlockTester <: Actor{Any}
    state::TestState
    valresp_count::Int
    cbcalled::Bool
    blocker::Addr
    core::Any
    BlockTester() = new(start, 0, false)
end

abstract type Read end
struct ReadVal <: Read end

function Circo.onspawn(me::BlockTester, service)
    me.blocker = spawn(service, Blocker(addr(me)))
    send(service, me, me.blocker, ReadVal())
end

struct ValResponse val end

function Circo.onmessage(me::Blocker, msg::ReadVal, service)
    send(service, me, me.tester, ValResponse(me.val))
end

struct Write val end
struct WriteAndBlock val end
struct UnBlockAndWrite val end
struct Die end

function Circo.onmessage(me::BlockTester, msg::ValResponse, service)
    me.valresp_count += 1
    @test me.state in (start, blocked, unblocked)
    if me.state == start
        @test isnothing(msg.val)
        send(service, me, me.blocker, WriteAndBlock(42))
        me.state = block_sent
    elseif me.state == blocked
        @test msg.val == 42
        send(service, me, me.blocker, Write(:delayed))
        if me.valresp_count < 100
            send(service, me, me.blocker, ReadVal())
        else
            send(service, me, me.blocker, UnBlockAndWrite(:unblock))
        end
    elseif me.state == unblocked
        @test msg.val == :delayed || msg.val == :unblock
        if msg.val == :delayed
            send(service, me, me.blocker, Die())
            die(service, me)
        else
            send(service, me, me.blocker, ReadVal())
        end
    end
end

struct BlockResponse end
struct CbNotification end

function Circo.onmessage(me::Blocker, msg::Write, service)
    @test me.val == :unblock || me.val == msg.val
    me.val = msg.val
end

function Circo.onmessage(me::Blocker, msg::WriteAndBlock, service)
    @test isnothing(me.val)
    me.val = msg.val
    block(service, me, UnBlockAndWrite; process_readonly = Read) do wakemsg # TODO also test without callback
        @test msg.val != wakemsg.val
        send(service, me, me.tester, CbNotification())
    end
    send(service, me, me.tester, BlockResponse())
end

function Circo.onmessage(me::BlockTester, msg::BlockResponse, service)
    @test me.state == block_sent
    me.state = blocked
    send(service, me, me.blocker, ReadVal())
end

struct UnBlockResponse end

function Circo.onmessage(me::Blocker, msg::UnBlockAndWrite, service)
    @test wake(service, me) == false
    me.val = msg.val
    send(service, me, me.tester, UnBlockResponse())
end

function Circo.onmessage(me::Blocker, ::Die, service)
    die(service, me)
end

function Circo.onmessage(me::BlockTester, msg::UnBlockResponse, service)
    @test me.state == blocked
    me.state = unblocked
    send(service, me, me.blocker, ReadVal())
end

function Circo.onmessage(me::BlockTester, msg::CbNotification, service)
    me.cbcalled = true
end

@testset "Blocking" begin
    tester = BlockTester()
    ctx = CircoContext(userpluginsfn=() -> [BlockService])
    scheduler = Scheduler(ctx, [tester])
    scheduler(;exit=true)
    Circo.shutdown!(scheduler)
    @test tester.cbcalled == true
end
