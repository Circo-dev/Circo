# SPDX-License-Identifier: MPL-2.0
using Circo

struct MigrateCommand
    topostcode::PostCode
    stayeraddress::Addr
end

struct MigrateDone
    newaddress::Addr
end

mutable struct Stayer <: AbstractActor{Any}
    oldmigrantaddress::Addr
    resultsholder_address::Addr
    responsereceived::Integer
    newaddress_selfreport::Addr
    newaddress_recepientmoved::Addr
    core
    Stayer(migrantaddress, resultsholder_address) = new(migrantaddress, resultsholder_address, 0)
end

struct SimpleRequest
    responseto::Addr
end

struct SimpleResponse end

struct Results
    stayer::Stayer
end

mutable struct ResultsHolder <: AbstractActor{Any}
    results::Results
    core
    ResultsHolder() = new()
end

mutable struct Migrant <: AbstractActor{Any}
    stayeraddress::Addr
    core
    Migrant() = new()
end
