# SPDX-License-Identifier: MPL-2.0
module Profiles

import CircoCore
using ..Circo,
    Circo.Migration,
    Circo.Cluster,
    Circo.WebSocket,
    Circo.Monitor,
    Circo.InfotonOpt,
    Circo.DistributedIdentities,
    Circo.IdRegistry

const AbstractProfile = CircoCore.Profiles.AbstractProfile
const core_plugins = CircoCore.Profiles.core_plugins
const MinimalProfile = CircoCore.Profiles.MinimalProfile
const EmptyProfile = CircoCore.Profiles.EmptyProfile
const DefaultProfile = CircoCore.Profiles.DefaultProfile

struct ClusterProfile <: AbstractProfile
    options
    ClusterProfile(;options...) = new(options)
end

function CircoCore.Profiles.core_plugins(profile::ClusterProfile)
    options = profile.options
    return [
        InfotonOpt.Optimizer,
        MigrationService,
        ClusterService,
        DistIdService,
        IdRegistryService,
        WebsocketService,
        MonitorService,
        core_plugins(DefaultProfile(;options...))...,
    ]
end

end
