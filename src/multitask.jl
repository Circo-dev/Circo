module MultiTask

using Plugins
using ..Circo
using Circo.Block


export awaitresponse, MultiTaskService

struct TaskPool
    tasks::Vector{Task}
    maxsize::Int
    taskcreator
    TaskPool(taskcreator; maxsize=1000, options...) = new(Vector{Task}(), maxsize, taskcreator)
end

gettask(tp::TaskPool) = begin
    if isempty(tp.tasks)
        retval = tp.taskcreator()
        if isdefined(Base, :errormonitor) # Not in 1.6
            errormonitor(retval)
        end
        return retval
    end
    return pop!(tp.tasks)
end

releasetask(tp::TaskPool, task::Task) = begin
    if length(tp.tasks) < tp.maxsize
        push!(tp.tasks, task)
    end
end

Base.empty!(tp::TaskPool) = empty!(tp.tasks)


schedulertask_creator(sdl) = () -> Task(() -> begin
    @debug "Starting event loop on new $(current_task())"
    try
        CircoCore.eventloop(sdl; remote=true)
    catch e
        @error "Error in scheduler task: $e" exception = (e, catch_backtrace())
    end
    @debug "Event loop exited on $(current_task())"
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

Circo.schedule_stop(mts::MultiTaskService, sdl) = begin
    empty!(mts.pool)
end

responsetype(::Type{<:Request}) = Response

# TODO The name of this function may be more specific. requestInNewTask? requestinBlockingTask ? sendBlockerMessage?
"""
    function awaitresponse(srv, me::Actor, to::Addr, msg::Request)

Send out `msg`, block the current Julia task and the `me` actor until a response is received, then return the response.

When a `Failure` is received, it will be thrown as exception.
This can be used to simplify code layout when the response is needed to continue operation.

The scheduler will continue to run using other Julia tasks while waiting for a response.
`me` will also be "blocked" (See [`block`](@ref)), meaning that messages arriving while waiting will be queued.
"""
function awaitresponse(srv, me::Actor, to::Addr, msg::Request)
    mts = plugin(srv, :multitask)
    if isnothing(mts)
         error("MultiTask plugin not loaded!") # TODO allow it for debugging (with blocking the only scheduler task)
    end 
    mts::MultiTaskService # TODO this breaks extensibility, check if performance gain is worth it (same as in Block)

    send(srv, me, to, msg)
    
    thistask = current_task()
    waketoken = msg.token
    block(srv, me, Union{Failure, responsetype(typeof(msg))};
        waketest = resp -> resp.body.token == waketoken
    ) do response
        @debug "Wake $(addr(me)) on $(current_task()) with $(response)"
        releasetask(mts.pool, current_task())
        yieldto(thistask, response)
    end
    response = yieldto(gettask(mts.pool))
    if response isa Failure
        throw(response)
    end
    return response
end

end # module
