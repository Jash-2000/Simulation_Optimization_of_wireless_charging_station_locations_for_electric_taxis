using JLD2
using FileIO
using LightXML
using MatrixNetworks
using SparseArrays

const ratio = pi/180	# multiplier for degree-to-radians conversion
const radius = 6371000	# radius of the earth in metres [1]

"""
Converts OSM data to a road network for the simulation.

Parameters
----------
osm_file: String
	Filename of the OSM file that saved with the extension osm.xml

Returns
--------
Saves network information to jld2 file called "preprocessing-3.jld2:
DIST: SparseArray{Int64, 2}
	The node incidence matrix of the road network containing distances in meters between nodes.
TIME: SparseArray{Int64, 2}
	The node incidence matrix of the road network containing travel time in _minutes_ between nodes. CHECK _minutes_.
LATTITUDE: Vector{Float64}
	The lattitudes of each node in the network. The ith element in the vector is the lattitude of the ith node in the network.
LONGITUDE: Vector{Float64}
	The longitudes of each node in the network. The ith element in the vector is the longitude of the ith node in the network.

Notes
-----
-To preprecess a large OSM file such like the one of Karlsruhe it takes a long time.
-To reduce preprocessing time it is important to filter OSM file. Follow directions given in "preprocessing_readme.md".
"""

# =================================================================
# PREPROCESSING STEP 1: parse osm
data = root(parse_file("data/karlsruhe-cut.osm.xml"))
nodes = data["node"]
ways = data["way"]
num_nodes = length(nodes)

osm_to_ind = Dict{Int64, Int64}()
LAT = zeros(Float64, num_nodes)
LON = zeros(Float64, num_nodes)

for v = 1:num_nodes
	node = nodes[v]
	osm_to_ind[parse(Int64, attribute(node, "id"))] = v
	LAT[v] = parse(Float64, attribute(node, "lat"))
	LON[v] = parse(Float64, attribute(node, "lon"))
end

DIST = spzeros(Float64, num_nodes, num_nodes)
SPEED = spzeros(Int64, num_nodes, num_nodes)

println("preprocessing ways")
for i = 1:length(ways)
	if (i % 1000 == 0)
		print(i)
	end
	nodes = ways[i]["nd"]
	tags = ways[i]["tag"]

	oneway = false
	defspeed_forward = 50
	defspeed_backward = 50
	maxspeed_forward = -1
	maxspeed_backward = -1
	use_maxspeed = false

	for j = 1:length(tags)
		k = attribute(tags[j], "k")
		v = attribute(tags[j], "v")

		if (k == "oneway") && (v == "yes")
			oneway = true
			continue
		end

		try
			v = parse(Int64, v)
		catch
			continue
		end

		if (k == "maxspeed") || (k == "maxspeed:practical") || (k == "maxspeed:advisory")
			maxspeed_forward = v
			maxspeed_backward = v
		elseif k == "maxspeed:forward"
			maxspeed_forward = v
		elseif k == "maxspeed:backward"
			maxspeed_backward = v
		elseif k == "highway"
			if v == "motorway"
				# Usually the maxspeed can be kept for long distances, but these
				# roads can be sensitive to long traffic jams. Usually forbidden
				# for slow traffic (pedestrians, cyclists, agricultural, ...) [2]
				use_maxspeed = true
			elseif v == "trunk"
				# Similar to motorways, but these roads can have level crossings,
				# so the stretches where the maximum speed can be reached are shorter.
				# Best avoided when using slow vehicles (sometimes forbidden, depending
				# on the local legislation). [2]
				use_maxspeed = true
			elseif v == "motorway_link"
				# Used for on- and off-ramps or complete motorway junctions. Reachable
				# speed depends a lot on curvature, usually around 60-90 km/h. [2]
				defspeed_forward = 75
			elseif v == "unclassified"
				# These roads usually connect farms, isolated houses and small hamlets
				# through the countryside to bigger residential areas. Due to lack
				# of traffic signs, they often have a speed limit way faster than
				# can be driven safely. Speed on a well-maintained but unfamiliar
				# unclassified road will rarely exceed 50 km/h. [2]
				defspeed_forward = 30
			elseif v == "residential"
				# Residential roads are found in a residential area, so usually
				# have a speed limit of 50 km/h to 30 km/h, with a lot of traffic
				# calming features. [2]
				defspeed_forward = 40
			end
		end
	end

	if use_maxspeed
		if maxspeed_forward > -1
			defspeed_forward = maxspeed_forward
		end
		if maxsp_backward > -1
			defspeed_backward = maxspeed_backward
		end
	else
		defspeed_backward = defspeed_forward
	end

	for j = 2:length(nodes)
		try
			u = osm_to_ind[parse(Int64, attribute(nodes[j-1], "ref"))]
			v = osm_to_ind[parse(Int64, attribute(nodes[j], "ref"))]
			ulat = ratio * LAT[u]
			ulon = ratio * LON[u]
			vlat = ratio * LAT[v]
			vlon = ratio * LON[v]
			dist = max(1.0, radius * acos(sin(ulat) * sin(vlat) + cos(ulat) * cos(vlat) * cos(ulon - vlon)))
			DIST[u,v] = dist
			SPEED[u,v] = defspeed_forward
			if !oneway
				DIST[v,u] = dist
				SPEED[v,u] = defspeed_backward
			end
		catch
		# println("missing node")
		end
	end
end

DIST1, DIST1_includes = largest_component(DIST)
SPEED1, SPEED1_includes = largest_component(SPEED)

LAT1 = Vector{Float64}()
LON1 = Vector{Float64}()

for v = 1:num_nodes
	if DIST1_includes[v]
		push!(LAT1, LAT[v])
		push!(LON1, LON[v])
	end
end

println("\nPREPROCESSING STEP 1: parse osm")
println("DIST  : $(size(DIST1,1)) nodes and $(nnz(DIST1)) arcs")
println("SPEED : $(size(SPEED1,1)) nodes and $(nnz(SPEED1)) arcs")

save("preprocessing-1.jld2",
	 "DISTANCE", DIST1, "SPEED", SPEED1, "LATITUDE", LAT1, "LONGITUDE", LON1)

# =================================================================
# PREPROCESSING STEP 2A: line smoothing of bidirectional paths

data = load("preprocessing-1.jld2")
DIST = copy(data["DISTANCE"])
SPEED = copy(data["SPEED"])
LAT = copy(data["LATITUDE"])
LON = copy(data["LONGITUDE"])
num_nodes = DIST.m

# make a subgraph comprising nodes w/ exactly 2 incident bidirectional arcs
# the subgraph will be a set of disconnected bidirectional paths
deg2 = copy(DIST)

println("Find bidrectional arcs for simplication")
for v = 1:num_nodes
	if (v % 1000 == 0)
		print(v)
	end

    nzu = findnz(deg2[:,v])[1]
    nzw = findnz(deg2[v,:])[1]
    bool = (length(nzu) == 2) && (length(nzw) == 2) && (sort(nzu) == sort(nzw)) # (u)<->(v)<->(w)
    if !bool
        for u in nzu
            deg2[u,v] = 0.0
        end
        for w in nzw
            deg2[v,w] = 0.0
        end
    end
end

dropzeros!(deg2)

# replace paths by a single bidirectional shortcut arc connecting the two end nodes
# insert shortcut arc into the original graph and delete the replaced arcs
println("replace bidirectional arcs")
for v = 1:num_nodes
	if (v % 1000 == 0)
		print(v)
	end

    nzu = findnz(deg2[:,v])[1]
    nzw = findnz(deg2[v,:])[1]
    if (length(nzu) == 1) && (length(nzw) == 1) # begin at path source
        w1 = v
        w2 = nzw[1]
        dist = DIST[w1,w2]
        speed = SPEED[w1,w2]
		DIST[w1,w2] = 0.0
        DIST[w2,w1] = 0.0
		SPEED[w1,w2] = 0.0
        SPEED[w2,w1] = 0.0
        nzw2 = findnz(deg2[w2,:])[1]
        while length(nzw2) == 2
			w0 = w1
            w1 = w2
            w2 = nzw2[1] == w0 ? nzw2[2] : nzw2[1]
            dist += DIST[w1,w2]
            DIST[w1,w2] = 0.0
			DIST[w2,w1] = 0.0
            SPEED[w1,w2] = 0.0
			SPEED[w2,w1] = 0.0
            nzw2 = findnz(deg2[w2,:])[1]
        end
        DIST[v,w2] = dist
		DIST[w2,v] = dist
        SPEED[v,w2] = speed
		SPEED[w2,v] = speed
    end
end

dropzeros!(DIST)
dropzeros!(SPEED)

# get largest connected component again to drop the now disconnected nodes
DIST1, DIST1_includes = largest_component(DIST)
SPEED1, SPEED1_includes = largest_component(SPEED)

LAT1 = Vector{Float64}()
LON1 = Vector{Float64}()

for v = 1:num_nodes
    if DIST1_includes[v]
		push!(LAT1, LAT[v])
		push!(LON1, LON[v])
    end
end

println("\nPREPROCESSING STEP 2A: line smoothing of bidirectional paths")
println("DIST  : $(size(DIST1,1)) nodes and $(nnz(DIST1)) arcs")
println("SPEED : $(size(SPEED1,1)) nodes and $(nnz(SPEED1)) arcs")

save("preprocessing-2A.jld2",
	 "DISTANCE", DIST1, "SPEED", SPEED1, "LATITUDE", LAT1, "LONGITUDE", LON1)

# =================================================================
# PREPROCESSING STEP 2B: line smoothing of unidirectional paths

data = load("preprocessing-2A.jld2")
DIST = copy(data["DISTANCE"])
SPEED = copy(data["SPEED"])
LAT = copy(data["LATITUDE"])
LON = copy(data["LONGITUDE"])
num_nodes = DIST.m

# make a subgraph comprising nodes w/ exactly 1 incoming and 1 outgoing arc from/to 2 distinct nodes
# the subgraph will be a set of disconnected unidirectional paths
deg2 = copy(DIST)
println("Find unidirectional arcs for simplication")
for v = 1:num_nodes
	if (v % 1000 == 0)
		print(v)
	end
    nzu = findnz(deg2[:,v])[1]
    nzw = findnz(deg2[v,:])[1]
    bool = (length(nzu) == 1) && (length(nzw) == 1) && (nzu[1] != nzw[1]) # (u)->(v)->(w) where (u)~=(w)
    if !bool
        for u in nzu
            deg2[u,v] = 0.0
        end
        for w in nzw
            deg2[v,w] = 0.0
        end
    end
end

dropzeros!(deg2)

# replace paths by a single unidirectional shortcut arc connecting the two end nodes
# insert shortcut arc into the original graph and delete the replaced arcs
println("replace unidirectional arcs")
for v = 1:num_nodes
	if (v % 1000 == 0)
		print(v)
	end
    nzu = findnz(deg2[:,v])[1]
    nzw = findnz(deg2[v,:])[1]
    if (length(nzu) == 0) && (length(nzw) == 1) # begin at path source
        w1 = v
        w2 = nzw[1]
        dist = DIST[w1,w2]
        speed = SPEED[w1,w2]
		DIST[w1,w2] = 0.0
		SPEED[w1,w2] = 0.0
        nzw2 = findnz(deg2[w2,:])[1]
        while length(nzw2) == 1
            w1 = w2
            w2 = nzw2[1]
            dist += DIST[w1,w2]
            DIST[w1,w2] = 0.0
            SPEED[w1,w2] = 0.0
            nzw2 = findnz(deg2[w2,:])[1]
        end
        DIST[v,w2] = dist
        SPEED[v,w2] = speed
    end
end

dropzeros!(DIST)
dropzeros!(SPEED)

# get largest connected component again to drop the now disconnected nodes
DIST1, DIST1_includes = largest_component(DIST)
SPEED1, SPEED1_includes = largest_component(SPEED)

LAT1 = Vector{Float64}()
LON1 = Vector{Float64}()

for v = 1:num_nodes
    if DIST1_includes[v]
		push!(LAT1, LAT[v])
		push!(LON1, LON[v])
    end
end

println("\nPREPROCESSING STEP 2B: line smoothing of unidirectional paths")
println("DIST  : $(size(DIST1,1)) nodes and $(nnz(DIST1)) arcs")
println("SPEED : $(size(SPEED1,1)) nodes and $(nnz(SPEED1)) arcs")

save("preprocessing-2B.jld2",
	 "DISTANCE", DIST1, "SPEED", SPEED1, "LATITUDE", LAT1, "LONGITUDE", LON1)

# =================================================================
# PREPROCESSING STEP 3: time matrix

data = load("preprocessing-2B.jld2")
DIST = copy(data["DISTANCE"])
SPEED = copy(data["SPEED"])
LAT = copy(data["LATITUDE"])
LON = copy(data["LONGITUDE"])
num_nodes = DIST.m

TIME = copy(DIST)

for u = 1:num_nodes
	nzv = findnz(TIME[u,:])[1]
	for v in nzv
		TIME[u,v] /= (SPEED[u,v]/3.6)
	end
end

println("\nPREPROCESSING STEP 3: time matrix")
println("TIME  :     $(size(TIME,1)) nodes and $(nnz(TIME)) arcs")

save("preprocessing-3.jld2",
	 "DISTANCE", DIST, "TIME", TIME, "LATITUDE", LAT, "LONGITUDE", LON)

# =================================================================
# REFERENCES

# [1] Rolf Nungesser's Master Thesis
# [2] https://wiki.openstreetmap.org/wiki/Routing
