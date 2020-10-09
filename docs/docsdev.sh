#!/bin/bash
# Uses globally installed local-web-server (npm i local-web-server -g)

julia --project=docs -e '
          using Pkg;
          Pkg.develop(PackageSpec(path=pwd()));
          include("docs/make.jl");'

cd docs/build && ws -p 8001
