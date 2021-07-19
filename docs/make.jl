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

withenv("GITHUB_REPOSITORY" => "Circo-dev/docs-Circo") do
    deploydocs(
        repo = "github.com/Circo-dev/docs-Circo.git",
        branch = "main",
        devbranch = "main",
        push_preview = true
    )
end