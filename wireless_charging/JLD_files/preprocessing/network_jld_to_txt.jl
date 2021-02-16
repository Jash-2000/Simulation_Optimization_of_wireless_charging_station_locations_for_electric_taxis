using JLD
using SparseArrays
using DelimitedFiles

cd("/Users/jadexiao/Desktop/evrouting/wireless_charging")

jldopen("data/network-karlsruhe.jld", "r") do fn
    global DIST = read(fn, "DISTANCE")
    global TIME = read(fn, "TIME")
    global LAT = read(fn, "LATITUDE")
    global LON = read(fn, "LONGITUDE")
    global num_nodes = DIST.m
    global num_arcs = nnz(DIST)
end

source = zeros(Int64, num_arcs)
target = zeros(Int64, num_arcs)
dist = zeros(Float64, num_arcs)
time = zeros(Float64, num_arcs)

a = 0
for u = 1:num_nodes
    println("arc $a/$num_arcs")
    nzv = findnz(DIST[u,:])[1]
    for v in nzv
        global a += 1
        source[a] = u
        target[a] = v
        dist[a] = DIST[u,v]
        time[a] = TIME[u,v]
    end
end

@assert i == num_arcs

writedlm("data/source.txt", source)
writedlm("data/target.txt", target)
writedlm("data/dist.txt", dist)
writedlm("data/time.txt", time)
writedlm("data/lat.txt", lat)
writedlm("data/lon.txt", lon)
