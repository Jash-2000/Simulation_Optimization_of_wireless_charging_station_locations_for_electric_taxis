using Random
using DelimitedFiles
using JLD2
using FileIO

# This script is used to find home nodes for each taxi

const conversion = pi/180 # multiplier for degree-to-radians conversion
const radius = 6371000 # radius of the Earth in metres
Random.seed!(10)

# load data
jld = load("data/network-karlsruhe.jld2")
LAT = jld["LATITUDE"] * conversion
LON = jld["LONGITUDE"] * conversion


# location of Karlsruhe Palace 
clat = 49.01355518465439 * conversion
clon = 8.40444036461422 * conversion

home_nodes = Vector{Int64}(undef, 0)
home_lat = Vector{Float64}(undef, 0)
home_lon = Vector{Float64}(undef, 0)

# Keep finding home nodes until there is one for each taxi
while length(home_nodes) < 100
    node = rand(1:length(LAT))
    nlat = LAT[node]
    nlon = LON[node]
    ratio = sin(clat) * sin(nlat) + cos(clat) * cos(nlat) * cos(clon - nlon)
    d = radius * acos(ratio)
    # If the node is within 10km of Karlsruhe Palace...
    if d < 10000 
        # ...add node to list of home nodes.
        push!(home_nodes, node)
        push!(home_lat, nlat)
        push!(home_lon, nlon)
        println("Add home node ", node)
    end
end
println("The home nodes are ", home_nodes)

# Write home nodes to txt files
writedlm(joinpath("data","home_nodes.txt"), home_nodes)

# # Write latitude and longitudes of home nodes for plotting
# writedlm(joinpath("data","NODE_Y.txt", home_lat/conversion) 
# writedlm(joinpath("data","NODE_X.txt", home_lon/conversion)


