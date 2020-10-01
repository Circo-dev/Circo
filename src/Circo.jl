module Circo

using Reexport
using Plugins
import Base: show

@reexport using CircoCore

export MonitorService, Debug, cli, Host, JS,
    ClusterService, ClusterActor, NodeInfo, Joined, PeerListUpdated,
    MigrationService, migrate_to_nearest, MigrationAlternatives, RecipientMoved,
    WebsocketService

const actor_activity_sparse16 = CircoCore.actor_activity_sparse16
const actor_activity_sparse256 = CircoCore.actor_activity_sparse256
const apply_infoton = CircoCore.apply_infoton
const letin_remote = CircoCore.letin_remote
const localdelivery = CircoCore.localdelivery
const localroutes = CircoCore.localroutes
const prepare = CircoCore.prepare
const schedule_start = CircoCore.schedule_start
const schedule_pause = CircoCore.schedule_pause
const schedule_continue = CircoCore.schedule_continue
const schedule_stop = CircoCore.schedule_stop
const scheduler_infoton = CircoCore.scheduler_infoton
const specialmsg = CircoCore.specialmsg
const stage = CircoCore.stage

include("host.jl")
include("monitor.jl")
include("cluster/cluster.jl")
include("migration.jl")
include("interregion/websocket.jl")
include("debug/debug.jl")
include("profiles.jl")
include("cli/circonode.jl")

end # module
