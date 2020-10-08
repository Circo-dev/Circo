# Plugin development

Please also read the documentation of [Plugins.jl](https://github.com/tisztamo/Plugins.jl)


For sample code, look for any plugin in the source code. E.g. [OnMessage](https://github.com/Circo-dev/CircoCore.jl/blob/master/src/onmessage.jl) is trivial, [MsgStats](https://github.com/Circo-dev/Circo/blob/master/src/debug/msgstats.jl) and [Event](https://github.com/Circo-dev/CircoCore.jl/blob/master/src/event.jl) are a bit more involved.


## Plugin Lifecycle

Following is the list of hooks to implement in plugins. Time usually goes top -> down, except:

- When there is no empty line between hooks, then the call order is not defined.
- Indented blocks may be called repeatedly

```
customfield(plugin, parent_type) # Provide extra fields to core types

prepare(plugin, ctx) # Initial stage, plugins can use eval() here

# Execution flow will reach top-level to allow staged code to run

setup!(plugin, scheduler) # Allocate resources

    schedule_start(plugin, scheduler) # Scheduling may be stopped and restarted several times

        schedule_continue(plugin, scheduler) # Scheduling continues after stop or pause

            localdelivery() # Deliver a message to an actor (e.g. call onmessage)
            localroutes() # Handle messages that are targeted to actors not (currently) scheduled locally (e.g. during migration).
            specialmsg() # Handle messages that are targeted to the scheduler (to the box 0)
            remoteroutes() # Deliver messages to external targets
            actor_activity_sparse16() # An actor just received a message, called with 1/16 probability
            actor_activity_sparse256() # An actor just received a message, called with 1/256 probability
            spawnpos() # Provide initial position of an actor when it is spawned

            letin_remote() # Let external sources push messages into the queue (using deliver!).

        schedule_pause(plugin, scheduler) # Scheduling is paused for a short time, e.g. to optimize code

        stage(plugin, scheduler, stagenum) # Next stage TODO not implemented

    schedule_stop(plugin, scheduler) # Scheduling is stopped for a potentially longer period

shutdown!(plugin, scheduler) # Release resources
```

If you need a new hook, please file an issue to discuss your use case and find the best way to implement it!