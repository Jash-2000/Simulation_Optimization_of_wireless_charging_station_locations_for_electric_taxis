using CSV
using JLD
using SparseArrays
using DelimitedFiles

const ratio = pi/180    # multiplier for degree-to-radians conversion
const radius = 6371000  # radius of the earth in metres

cd("/Users/jadexiao/Desktop/evrouting/wireless_charging")

jldopen("data/network-karlsruhe.jld", "r") do fn
    global LAT = read(fn, "LATITUDE")
    global LON = read(fn, "LONGITUDE")
    global num_nodes = length(LAT)
    for v = 1:num_nodes
        LAT[v] *= ratio
        LON[v] *= ratio
    end
end

open("data/ranks-karlsruhe.csv", "r") do fn
   data = CSV.read(fn)
   global num_ranks = size(data,1)
   global RLAT = zeros(Float64, num_ranks)
   global RLON = zeros(Float64, num_ranks)
   for r = 1:num_ranks
       RLAT[r] = ratio * data.LATITUDE[r]
       RLON[r] = ratio * data.LONGITUDE[r]
   end
end

nearest_node = zeros(Int64, num_ranks)

for r = 1:num_ranks
    println("rank $r/$num_ranks")
    node = 0
    dist = Inf
    rlat = RLAT[r]
    rlon = RLON[r]

    for v = 1:num_nodes
        vlat = LAT[v]
        vlon = LON[v]
        d = radius * acos(sin(rlat) * sin(vlat) + cos(rlat) * cos(vlat) * cos(rlon - vlon))
        if d < dist
            node = v
            dist = d
        end
    end

    nearest_node[r] = node
end

writedlm("data/rank_to_nearest_node.txt", nearest_node)
