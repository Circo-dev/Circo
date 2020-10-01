# SPDX-License-Identifier: LGPL-3.0-only
include("migrate-base.jl")
using Test
using Circo

function Circo.onmessage(me::Migrant, message::MigrateCommand, service)
    @debug "MigrateCommand"
    me.stayeraddress = message.stayeraddress
    migrate(service, me, message.topostcode)
end

function Circo.onmessage(me::Stayer, message::MigrateDone, service)
    @debug "MigrateDone received: $message"
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

ctx = CircoContext(; userpluginsfn = () -> [ClusterService(), MigrationService()])

function migratetoremote(targetpostcode, resultsholder_address)
    migrant = Migrant()
    scheduler = ActorScheduler(ctx, [migrant])
    stayer = Stayer(addr(migrant), Addr(resultsholder_address))
    schedule!(scheduler, stayer)
    cmd = MigrateCommand(targetpostcode, addr(stayer))
    deliver!(scheduler, addr(migrant), cmd)
    scheduler(; remote=true)
    println("Source Exited")
    Circo.shutdown!(scheduler)
end
