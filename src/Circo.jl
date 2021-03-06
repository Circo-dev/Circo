# SPDX-License-Identifier: MPL-2.0
module Circo

using Reexport
using Plugins
import Base: show

@reexport using CircoCore

export Debug, Host, JS, registermsg,
    Joined, PeerListUpdated

const call_lifecycle_hook = CircoCore.call_lifecycle_hook

const deliver! = CircoCore.deliver!

# Actor lifecycle callbacks
const onspawn = CircoCore.onspawn
const onmessage = CircoCore.onmessage

"""
    onmigrate(me::Actor, service)

Lifecycle callback that marks a successful migration.

It is called on the target scheduler, before any messages will be delivered.

Note: Do not forget to import it or use its qualified name to allow overloading!

# Examples
```julia
function Circo.onmigrate(me::MyActor, service)
    @info "Successfully migrated, registering a name on the new scheduler"
    registername(service, "MyActor", me)
end
```
"""
function onmigrate(me::Actor, service) end

# Hooks
const actor_activity_sparse16 = CircoCore.actor_activity_sparse16
const actor_activity_sparse256 = CircoCore.actor_activity_sparse256
const letin_remote = CircoCore.letin_remote
const localdelivery = CircoCore.localdelivery
const localroutes = CircoCore.localroutes
const prepare = CircoCore.prepare
const schedule_start = CircoCore.schedule_start
const schedule_pause = CircoCore.schedule_pause
const schedule_continue = CircoCore.schedule_continue
const schedule_stop = CircoCore.schedule_stop
const specialmsg = CircoCore.specialmsg
const stage = CircoCore.stage

function monitorprojection end
function monitorextra end

const NameQuery = CircoCore.Registry.NameQuery
const NameResponse = CircoCore.Registry.NameResponse

include("host.jl")
include("monitor.jl")
include("cluster/cluster.jl")
include("migration.jl")
include("block.jl")
include("infotonopt.jl")
include("outer/http.jl")
include("outer/websocket.jl")
include("debug/debug.jl")
include("profiles.jl")
include("cli/circonode.jl")

__init__() = Plugins.register(HostServiceImpl)
end # module
