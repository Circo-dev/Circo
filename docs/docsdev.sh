#!/bin/bash
# Uses globally installed local-web-server (npm i local-web-server -g)

julia --project docs/make.jl

cd docs/build && ws -p 8001
