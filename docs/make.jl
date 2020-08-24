using Documenter, Circo

makedocs(
    modules = [Circo],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "Schaffer Krisztian",
    sitename = "Circo.jl",
    pages = Any["index.md"]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/tisztamo/Circo.jl.git",
    push_preview = true
)
