include("types.jl")

"""
Loads the road network.

Parameters
----------
none

Returns
--------
network: Network
    A network struct as defined in types.jl that contains the road network for the simulation.

Notes
------
-The road network must be saved in the data folder as "network-karlsruhe.jld2". \n
-Network saved as vector of lattitude and longitudes keyed "LATTITUDE" and "LONGITUDE" respectively and 
node incidence network matrices of distance and time keyed "DISTANCE" and "TIME".
"""
function load_network()
    jld = load(joinpath("data", "network-karlsruhe.jld2"))
    return Network(jld["LATITUDE"], jld["LONGITUDE"], jld["DISTANCE"], jld["TIME"])
end

"""
Gets latitude and longitude of a node in the network.

Parameters
----------
node_id: Int64
    The node id for which the lattitude and longitude is desired.
net: Network
    The network which in which the node belongs.

Returns
--------
coords: Tuple{Float64, Float64}
    The coordinates (lattitude and longitude) of the node with the ID node_id.
"""
function node_location(node_id::Int64, net::Network)
    return (net.Lat[node_id],net.Long[node_id])
end

"""
Removes the trips that occur before START time.

Parameters
----------
trips: Vector{Trips}
    Contains the list of the precomputed taxi trips used in the simulation.

Returns
-------
trips: Vector{Trips}
    Contains the list of the precomputed taxi trips that occur after START time.

Notes
-----
-The time of the remaining trips is adjusted to be consistent with simulation time. \n
-START is defined in parameters.jl and is the time in minutes after Saturday midnight that the 
simulation starts. START must be a multiple of 60.
"""
function extract_trips(trips)

    for i in 1:length(trips)
        #trips.tripID = i
        if trips[i].time >= START
            trips = trips[i:length(trips)]
            break
        end
    end
    for i in 1:length(trips)
        trips[i].time -= START
    end
    return trips
end

"""
Loads the trip data.

Parameters
----------
none

Returns
-------
trips: Vector{trips}
    A list of the precomputed taxi trips for the simulation.

Notes
-----
-The precomputed taxi trips must be saved in the "data" folder as "trips-karlsruhe.jld2" with the key "trips".
"""
function load_trips()
    println(joinpath("data", "trips-karlsruhe1.jld2"))
    jld = load(joinpath("data", "trips-karlsruhe.jld2"))
    trips = extract_trips(jld["trips"])
    return trips
end

"""
Loads rank data and prepares simulation for execution.

Parameters
----------
sim: Simulation
    The SimJulia simulation instance that controls taxi simulation.

Returns
-------
data: Data
    A struct defined in types.jl that contains taxi rank information.

status: Status
    A struct defined in types.jl that stores rank and taxi data as simulation runs.

log: Log
    A struct defined in types.jl that tracks taxi and rank metrics during simulation.

Notes
-----
-Rank data must be stored in "data" folder as "ranks-karlsruhe.csv". \n
-A list of home nodes (node IDs) for each taxi must be stored in the "data" folder as "home_nodes.txt".
"""
function load_data(sim::Simulation)
    df = CSV.File(joinpath("data", "ranks-karlsruhe.csv")) |> DataFrame
    home_nodes_df = readdlm(joinpath("data", "home_nodes.txt"), '\t', Int64)
    num_ranks = size(df, 1)
    num_taxis = sum(df.TAXIS_ELECTRIC) + sum(df.TAXIS_COMBUSTION)
    print("\n\n The total number of taxis being used in our simulation is equal to : ")
    print(num_taxis)
    print("\n\n")
    wireless_chargers = df.CHARGERS_WIRELESS
    plugin_chargers = df.CHARGERS_PLUGIN
    
    data = Data(num_ranks, num_taxis)
    status = Status(num_ranks, num_taxis)
    log = Log(num_ranks, num_taxis, wireless_chargers, plugin_chargers)
    tID = 0

    for rID = 1:num_ranks
        data.rank_node[rID] = df.NODE[rID]
        data.rank_popularity[rID] = df.POPULARITY[rID]
        data.rank_capacity[rID] = df.CAPACITY[rID]
        data.rank_name[rID] = df.NAME[rID]
        data.rank_init_taxi[rID] = df.TAXIS_COMBUSTION[rID] + df.TAXIS_ELECTRIC[rID]
        
        ne = df.TAXIS_ELECTRIC[rID]
        nc = df.TAXIS_COMBUSTION[rID]
        status.rank_volume[rID] = ne + nc

        for i = 1:ne
            tID += 1
            push!(status.rank_queue_electric[rID], tID)
            status.taxi_loc[tID] = rID
            status.taxi_origin[tID] = rID
            status.taxi_soc[tID] = SOC_nominal
            status.taxi_home_node[tID] = home_nodes_df[tID,1]
        end

        for i = 1:nc
            tID += 1
            if ONE_QUEUE
                push!(status.rank_queue_electric[rID],tID)
            else
                push!(status.rank_queue_combustion[rID], tID)
            end
            status.taxi_loc[tID] = rID
            status.taxi_origin[tID] = rID
            status.taxi_soc[tID] = Inf
            status.taxi_home_node[tID] = home_nodes_df[tID,1]
        end

        np = df.CHARGERS_PLUGIN[rID]
        nw = df.CHARGERS_WIRELESS[rID]

        if np > 0
            status.rank_chargers_plugin[rID] = Resource(sim, np)
            if nw > 0
                status.rank_chargers_wireless[rID] = Resource(sim, nw)
                data.rank_mode[rID] = "mixed"
            else
                status.rank_chargers_wireless[rID] = nothing
                data.rank_mode[rID] = "plugin"
            end
        else
            status.rank_chargers_plugin[rID] = nothing
            if nw > 0
                status.rank_chargers_wireless[rID] = Resource(sim, nw)
                data.rank_mode[rID] = "wireless"
            else
                status.rank_chargers_wireless[rID] = nothing
                data.rank_mode[rID] = nothing
            end
        end
    end

    return data, status, log
end

"""
Precomputes taxi trips for simulation.

Parameters
----------
net: Network
    The road network taxis travel around.
data: Data
    A struct that contains information about the taxi ranks.
ind1: Int64
    The index of the first trip in "call-karlsuhe.csv" to precompute.
ind2:
    The index of the final trip in "calls-karlsruhe.csv" to precompute.

Returns
-------
none

Notes
------
-The calls must be saved as "calls.karlsruhe.csv" in the "data" folder. \n
-Precomputed trips are saved as vector of trips in "trips-karlsruhe.jld2" in the "data" 
folder with the key "trips". \n
For each trip: \n
-The routes consists of route2 which is fastest route from source to target and route3
 which is the fastest route from the target to the nearest charging rank.\n
-wait is the time difference between the trip and the previous trip. \n
-time is the simulation time when the trip request is made. \n
-rID is the ID of the closest charging rank to the target of the trip.
"""
function precompute_trips(net::Network, data::Data, ind1::Int64, ind2::Int64)    
    node_rank = Dict{Int64,Int64}(data.rank_node[rID] => rID for rID in 1:data.num_ranks)
    rIDc = [rID for rID in 1:data.num_ranks if !isnothing(data.rank_mode[rID])]
    rIDc_node = data.rank_node[rIDc]

    num_trips = ind2 - ind1 + 1
    trips = Vector{Trip}(undef, num_trips)

    df = CSV.File(joinpath("data", "calls-karlsruhe.csv")) |> DataFrame

    for i = 1:num_trips
        ind = ind1 + i - 1
        wait = Float64(df.WAIT[ind])
        source = df.SOURCE[ind]
        target = df.TARGET[ind]
        time = Float64(df.TIME[ind])

        # compute route from source to target
        route2 = dijkstra(net, source, target)

        if haskey(node_rank, target) && !isnothing(data.rank_mode[node_rank[target]])
            # if target is a rank with chargers, stay there
            route3 = nothing
            rID = node_rank[target]
        else
            # else, compute route from target to nearest rank with chargers
            ind, route3 = dijkstra_taxi_to_nearest_charger(net, target, rIDc_node)
            rID = rIDc[ind]
        end

        trips[i] = Trip(wait, time, nothing, route2, route3, rID, true)
        println(i, "/", num_trips)
    end

    save(joinpath("data", "trips-karlsruhe.jld2"), "trips", trips)
    println("Saved to trips-karlsruhe.jld2")
end

"""
Saves the simulation log.

Parameters
----------
log: Log
    A struct defined in types.jl that contains simulation metrics about taxi trips and the ranks.

Returns
-------
none

Notes
-----
-The log is saved as a jld2 file named "log-karlsruhe.jld2" in the "data" folder with the key
"log".
"""
function save_log(log::Log)    
    save(joinpath("data", "log-karlsruhe.jld2"), "log", log)
    println("Saved to log-karlsruhe.jld2")
end

"""
Loads the taxi shift information.

Parameters
----------
none

Returns
--------
shifts: Array{Bool, 2}
    An array of size n*T where n is the number of taxis and T is the number of one hour time periods
    for which the shifts have been defined (168 corresponds to one week of shifts). Element n_i, T_j is 
    true if taxi n_i is operating during time period T_j.

Notes
------
-The shift schedule must be saved in the "data" folder as "taxi_shift_schedule.csv".
-A shift schedule can be generated using full_shift_model in taxiShifts.jl.
"""
function load_shifts()
    open("data/taxi_shift_schedule.csv") do fn
        shifts = CSV.File(fn, normalizenames=true) |> DataFrame
        shifts = convert(Array, shifts)
        return shifts
    end
end