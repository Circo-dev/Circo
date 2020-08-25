#!/bin/bash
# Uses globally installed local-web-server (npm i local-web-server -g)

julia --project make.jl

cd build && ws -p 8001