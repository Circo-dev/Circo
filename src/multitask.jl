module MultiTask

using Plugins
using ..Circo
using Circo.Block

export request, MultiTaskService

struct TaskPool
    tasks::Vector{Task}
    maxsize::Int
    taskcreator
    TaskPool(taskcreator; maxsize=1000, options...) = new(Vector{Task}(), maxsize, taskcreator)
end

gettask(tp::TaskPool) = begin
    if isempty(tp.tasks)
        return tp.taskcreator()
    end
    return shift!(tp.tasks)
end

releasetask(tp::TaskPool, task::Task) = begin
    if length(tp.tasks) < tp.maxsize
        push!(tp.tasks, task)
    end
end

schedulertask_creator(sdl) = () -> Task(() -> begin
    @info "Starting loop on $(current_task())"
    CircoCore.eventloop(sdl; remote=false)
end)

mutable struct MultiTaskService <: Plugin
    blockservice
    pool::TaskPool
    MultiTaskService(blockservice;options...) = new(blockservice)
end
Plugins.symbol(::MultiTaskService) = :multitask
Plugins.deps(::Type{MultiTaskService}) = [Circo.Block.BlockService]

__init__() = Plugins.register(MultiTaskService)

Plugins.setup!(mts::MultiTaskService, sdl) = begin
    mts.pool = TaskPool(schedulertask_creator(sdl))
end

responsetype(::Type{<:Request}) = Response

function request(srv, me::Actor, to::Addr, msg::Request)
    @info "request on $(current_task())"
    mts = plugin(srv, :multitask)
    isnothing(mts) && error("MultiTask plugin not loaded!")
    mts::MultiTaskService # TODO this breaks extensibility, check if performance gain is worth it (same as in Block)
    thistask = current_task()
    nexttask = gettask(mts.pool)

    send(srv, me, to, msg)
    block(srv, me, responsetype(typeof(msg)); waketest = resp -> resp.body.token == msg.token) do response
        @info "Wake on $(current_task())"
        releasetask(mts.pool, nexttask)
        x = yieldto(thistask, response)
        @show x
    end
    retval = yieldto(nexttask)
    return @show retval
end

end # module
