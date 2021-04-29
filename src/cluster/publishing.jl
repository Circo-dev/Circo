isnewinfo(me::ClusterActor, key, info) = get(me.myinfo.extrainfo, key, nothing) != info
isnewinfo(me::ClusterActor, addr, key, info) = get(me.peers[addr].extrainfo, key, nothing) != info


"""
    PublishInfo(key::Symbol, info::Any)

Send this to the cluster actor to publish any info in the "extrainfo"
dict of the node's NodeInfo, which is (currently) synchronized to every
peer in the cluster.
"""
struct PublishInfo
    key::Symbol
    info::Any
end

function Circo.onmessage(me::ClusterActor, msg::PublishInfo, service)
    isnewinfo(me, msg.key, msg.info) || return nothing
    me.myinfo.extrainfo[msg.key] = msg.info
    send_downstream(service, me, InfoUpdate(addr(me), addr(me), msg.key, msg.info))
    fire(service, me, PeerUpdated(deepcopy(me.myinfo), msg.key, deepcopy(msg.info)))
end

struct InfoUpdate
    addr::Addr
    creditto::Addr
    key::Symbol
    info::Any
end

function Circo.onmessage(me::ClusterActor, msg::InfoUpdate, service)
    msg.addr != addr(me) || return nothing
    isnewinfo(me, msg.addr, msg.key, msg.info) || return nothing
    me.peers[msg.addr].extrainfo[msg.key] = msg.info
    send_downstream(service, me, InfoUpdate(msg.addr, addr(me), msg.key, msg.info))
    msg.creditto != msg.addr && credit_friend(me, msg.creditto, service)
    fire(service, me, PeerUpdated(deepcopy(me.peers[msg.addr]), msg.key, deepcopy(msg.info)))
end

