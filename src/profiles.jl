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
        core_plugins(DefaultProfile(;options...))...,
        ClusterService(;options...),
        WebsocketService(;options...),
        MigrationService(;options...),
        MonitorService(;options...),
    ]
end

end
