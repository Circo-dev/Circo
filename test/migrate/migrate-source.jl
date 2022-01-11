# SPDX-License-Identifier: MPL-2.0
include("migrate-base.jl")
using Test
using Circo, Circo.Migration, Circo.Cluster

function Circo.onmessage(me::Migrant, message::MigrateCommand, service)
    @debug "$message"
    me.stayeraddress = message.stayeraddress
    migrate(service, me, message.topostcode)
end

function Circo.onmessage(me::Stayer, message::MigrateDone, service)
    @debug "$message"
    me.newaddress_selfreport = message.newaddress
    send(service, me, me.oldmigrantaddress, SimpleRequest(addr(me)))
end

function Circo.onmessage(me::Stayer, message::RecipientMoved, service)
    me.newaddress_recepientmoved = message.newaddress
    send(service, me, me.newaddress_recepientmoved, SimpleRequest(addr(me)))
end

function Circo.onmessage(me::Stayer, message::SimpleResponse, service)
    me.responsereceived += 1
    send(service, me, me.resultsholder_address, Results(me))
    send(service, me, me.newaddress_recepientmoved, Results(me))
    die(service, me)
end

ctx = CircoContext(userpluginsfn = () -> [MigrationService, ClusterService])

function migratetoremote(targetpostcode, resultsholder_address)
    migrant = Migrant()
    scheduler = Scheduler(ctx, [migrant])
    stayer = Stayer(addr(migrant), Addr(resultsholder_address))
    schedule!(scheduler, stayer)
    cmd = MigrateCommand(targetpostcode, addr(stayer))
    send(scheduler, addr(migrant), cmd)
    scheduler(; remote=true)
    println("Source Exited")
    Circo.shutdown!(scheduler)
end
