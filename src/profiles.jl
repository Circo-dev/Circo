module Profiles
using ..Circo
import CircoCore

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
        MigrationService(;options...),
        ClusterService(;options...),
        WebsocketService(;options...),
        MonitorService(;options...),
        core_plugins(DefaultProfile(;options...))...,
    ]
end

end
