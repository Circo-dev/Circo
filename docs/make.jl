using Documenter, Circo, Literate

# Generating to docs/src, was unable to load pages from a different directory
Literate.markdown("docs/src/tutorial.jl", "docs/src/"; documenter = true)

makedocs(
    modules = [Circo],
    format = Documenter.HTML(; prettyurls = true),
    authors = "Schaffer Krisztian",
    sitename = "Circo",
    pages = Any[
        "index.md",
        "install.md",
        "showcase.md",
        "tutorial.md",
        "infotons.md",
        "plugindev.md",
        "reference.md",
        "troubleshooting.md",
    ]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/Circo-dev/Circo-docs.git",
    branch="main",
    push_preview = true
)
