# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.Cluster
import Circo:onmessage, onmigrate

Circo.monitorextra(me::Cluster.ClusterActor) = begin
    i = 0
    upfriends = (;map(a-> begin i += 1; Symbol("up$i") => box(a) end, collect(keys(me.upstream_friends)))...)
    i = 0
    downfriends = (;map(a-> begin i += 1; Symbol("down$i") => box(a) end, collect(me.downstream_friends))...)
    return merge(upfriends, downfriends)
end

const PEER_COUNT = 50
const ROOT_COUNT = 1

ctx = CircoContext(target_module=@__MODULE__, profile=Circo.Profiles.ClusterProfile())

cluster = []
scheduler = Scheduler(ctx, [])
rootaddresses = []
for i in 1:ROOT_COUNT
    root = Cluster.ClusterActor(NodeInfo("#$(length(cluster))"), rootaddresses, emptycore(scheduler.service))
    push!(cluster, root)
    spawn(scheduler, root)
    scheduler(;remote=false)
    global rootaddresses = [string(addr(node)) for node in cluster]
end

for i in 1:PEER_COUNT - ROOT_COUNT
    node = Cluster.ClusterActor(NodeInfo("#$(length(cluster))"), rootaddresses, emptycore(scheduler.service))
    push!(cluster, node)
    spawn(scheduler, node)
    if rand() < 0.2  # Simulate parallel joins
        scheduler(;remote=false)
    end
end
scheduler(;remote=false)
avgpeers = sum([length(node.peers) for node in cluster]) / length(cluster)
maxpeerupdates = maximum([node.peerupdate_count for node in cluster])
avgpeerupdate = sum([node.peerupdate_count for node in cluster]) / length(cluster)
avgupstreamfriends = sum([length(node.upstream_friends) for node in cluster]) / length(cluster)
println("Avg peer count: $avgpeers; Peer update max: $maxpeerupdates avg: $avgpeerupdate; Upstream friends avg: $avgupstreamfriends")
@test avgpeers == PEER_COUNT
for i in 1:PEER_COUNT
    @test length(cluster[i].peers) == PEER_COUNT
    idx1 = rand(1:PEER_COUNT)
    node1 = cluster[idx1]
    idx2 = rand(1:PEER_COUNT)
    node2 = cluster[idx2]
    @test node1.peers[addr(node2)].addr == addr(node2)
    @test node2.peers[addr(node1)].addr == addr(node1)
end

for i=1:PEER_COUNT
    target = cluster[i]#rand(cluster)
    info = rand()
    send(scheduler, target, Cluster.PublishInfo(:key1, info))
    scheduler(;remote=false)
    for checked in cluster
        if addr(checked) != addr(target)
            @test checked.peers[addr(target)].extrainfo[:key1] == info
        end
    end
end

Circo.shutdown!(scheduler)

# !selected || selected.box == me.box || onpath( selected, me, [/down1|down2|down3|down4|down5|down6/], 4)
# !selected || selected.box == me.box || onpath( selected, me, [/up1|up2|up3|up4|up5|up6/], 4)
# me.box == "62fd4425de1910d0" ||me.box == "2c90b127d3913caf"
