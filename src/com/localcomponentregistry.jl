struct ComponentRegistryEntry
    tagname::String
    type::Type
end

struct LocalComponentRegistry
    cache::Dict{String, ComponentRegistryEntry}
    LocalComponentRegistry() = new(Dict())
end

const localcomponentregistry = LocalComponentRegistry()

function define(tagname, type)
    localcomponentregistry.cache[tagname] = ComponentRegistryEntry(tagname, type)
end

function getcomponent(tagname)
    if !haskey(localcomponentregistry.cache, tagname)
        throw("Component not defined: $(tagname)")
    end
    return localcomponentregistry.cache[tagname].type
end
