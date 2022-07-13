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
    return pop!(tp.tasks)
end

releasetask(tp::TaskPool, task::Task) = begin
    if length(tp.tasks) < tp.maxsize
        push!(tp.tasks, task)
    end
end

schedulertask_creator(sdl) = () -> Task(() -> begin
    @debug "Starting event loop on new $(current_task())"
    try
        CircoCore.eventloop(sdl; remote=true)
    catch e
        @error "Error in scheduler task: $e" exception = (e, catch_backtrace())
    end
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

# TODO The name of this function may be more specific. requestInNewTask? requestinBlockingTask ? sendBlockerMessage?
# TODO missing docs 
function request(srv, serializer::Actor, blocker::Addr, msg::Request)
    mts = plugin(srv, :multitask)
    isnothing(mts) && error("MultiTask plugin not loaded!")
    mts::MultiTaskService # TODO this breaks extensibility, check if performance gain is worth it (same as in Block)
    thistask = current_task()
    nexttask = gettask(mts.pool)

    send(srv, serializer, blocker, msg)
    
    block(srv, serializer, responsetype(typeof(msg)); 
        waketest = resp -> resp.body.token == msg.token
        ) do response
        @debug "Wake $(addr(serializer)) on $(current_task()) with $(msg)"
        releasetask(mts.pool, nexttask)
        yieldto(thistask, response)
    end
    return yieldto(nexttask)
end

end # module
