module Profiles

import CircoCore

const MinimalProfile = CircoCore.Profiles.MinimalProfile
const EmptyProfile = CircoCore.Profiles.EmptyProfile
const DefaultProfile = CircoCore.Profiles.DefaultProfile

struct ClusterProfile
    options
    ClusterProfile(options = NamedTuple()) = new(options)
end

function core_plugins(profile::ClusterProfile)
    options = profile.options
    return [
        ClusterService(;options = options),
        WebsocketService(;options = options),
        MigrationService(;options = options),
        MonitorService(;options = options),
        core_plugins(DefaultProfile(options))...
    ]
end

end
