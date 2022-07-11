module MultiTask

using Plugins
using ..Circo
using Circo.Blocking

export request

struct TaskPool
    tasks::Vector{Task}
    maxsize::Int
    creator
    TaskPool(creator; maxsize=1000, options...) = new(Vector{Task}(), maxsize, creator)
end

gettask(tp::TaskPool) = begin
    if isempty(tp.tasks)
        return tp.creator()
    end
    return shift!(tp.tasks)
end

releasetask(tp::TaskPool, task::Task) = begin
    if length(tp.tasks) < tp.maxsize
        push!(tp.tasks, task)
    end
end

mutable struct MultiTaskService <: Plugin
    blockservice
    pool::TaskPool
    MultiTaskService(blockservice;options...) = new(blockservice, TaskPool())
end
Plugins.symbol(::MultiTaskService) = :multitask
Plugins.deps(::MultiTaskService) = [Circo.Block.BlockService]

__init__() = Plugins.register(MultiTaskService)

nexttask(mts::MultiTaskService) = nexttask(mts.pool)

responsetype(Type{<:Request}) = Response

function request(wakecb, srv, me::Actor, to::Addr, msg::Request)
    mts = plugin(service, :multitask)
    isnothing(mts) && error("MultiTask plugin not loaded!")
    mts::MultiTaskService # TODO this breaks extensibility, check if performance gain is worth it (same as in Blocking)
    thistask = current_task()
    nexttask = gettask(mts)

    send(srv, me, to, msg)
    block(srv, me, responsetype(typeof(msg)); waketest = resp -> resp.token == msg.token) do msg
        retval = wakecb(msg)
        releasetask(mts, nexttask)
        yieldto(thistask, retval)
    end
    yieldto(nexttask)
end

end # module
