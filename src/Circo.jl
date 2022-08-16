# SPDX-License-Identifier: MPL-2.0
module Circo

using Reexport
using Plugins
import Base: show

@reexport using CircoCore
export CircoCore

export Debug, Host, JS, registermsg,
    Joined, PeerListUpdated,
    @actor, @onspawn, @onmessage, @send, @spawn, @become, @die,
    @identity, @response, @fire

const call_lifecycle_hook = CircoCore.call_lifecycle_hook
const deliver! = CircoCore.deliver!
const onmessage = CircoCore.onmessage
const ontraitmessage = CircoCore.ontraitmessage
const traits = CircoCore.traits


# Plugin Hooks
const actor_activity_sparse16 = CircoCore.actor_activity_sparse16
const actor_activity_sparse256 = CircoCore.actor_activity_sparse256
const letin_remote = CircoCore.letin_remote
const actor_spawning = CircoCore.actor_spawning
const actor_dying = CircoCore.actor_dying
const actor_state_write = CircoCore.actor_state_write
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

include("lang/lang.jl")
include("host.jl")
include("monitor.jl")
include("cluster/cluster.jl")
include("migration.jl")
include("block.jl")
include("multitask.jl")
include("infotonopt.jl")
include("debug/debug.jl")
include("identity/identity.jl")
include("identity/transactions.jl")
include("identity/single_phase_commit.jl")
include("identity/idregistry.jl")
include("identity/leadgroup.jl")
include("outer/filesystem.jl")
include("outer/marshal.jl")
include("outer/http.jl")
include("outer/websocket.jl")
include("outer/websocketclient.jl")
include("com/com.jl")
include("persistence.jl")
include("profiles.jl")
include("cli/circonode.jl")

__init__() = Plugins.register(HostServiceImpl)
end # module
