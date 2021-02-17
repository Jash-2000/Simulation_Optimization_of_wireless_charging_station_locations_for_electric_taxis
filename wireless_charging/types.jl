"""

time - Time Elapsed in travelling on that path
energy - Energy consumed
path - vector of starting and ending nodes

"""
struct Route
    time::Union{Float64,Vector{Float64}}
    energy::Union{Float64,Vector{Float64}}
    path::Vector{Int64}
end


"""
This struct is used to define a trip. We do not take into account the taxi id as it is not of much significance( the first taxi in the queue would be acted upon).

wait - The wait time before a taxi reacts to the request.
time - Time at which the trip start ( i.e. start time of route1).
route1 - The route between the starting location of the taxi(source must be must be rank node) and the location of passenger
route2 - The route between the passenger starting position and the destination
route3 - The route between the node where the passeneger dropped off and the destination node(destination rank)
rID - Final(Destination) Rank ID
urgent - Additional feature (not added yet)
"""
mutable struct Trip
    #tripID::Int64
    wait::Float64
    time::Float64
    route1::Union{Nothing,Route}
    route2::Route
    route3::Union{Nothing,Route}
    rID::Int64
    urgent::Bool
end


"""
Struct that defines movement for Taxi_trip.

NOTE:
Currently not implemented into simulation, Move_taxi is.

"""
struct Move
    time::Float64
    start_coords::Tuple{Float64, Float64}
    end_coords::Tuple{Float64, Float64}

    function Move(t::Float64, start_coords::Tuple{Float64, Float64}, end_coords::Tuple{Float64, Float64})
        time = t
        start_coords = start_coords
        end_coords = end_coords
        return new(time, start_coords, end_coords)
    end
end

"""
Struct that defines the movement of taxis in simulation for visualisation.

NOTE:
When taxi enters service at rank this will be recorded as movement where start_time = end_time 
and start_coords = end_coords. 
"""
struct Move_taxi
    tID::Int64 
    start_time::Float64
    end_time::Float64
    start_coords::Tuple{Float64, Float64}
    end_coords::Tuple{Float64, Float64}

    function Move_taxi(ID::Int64, t_s::Float64, t_e::Float64, start_coords::Tuple{Float64, Float64}, end_coords::Tuple{Float64, Float64})
        tID = ID
        start_time = t_s
        end_time = t_e
        start_coords = start_coords
        end_coords = end_coords
        return new(tID, start_time,end_time, start_coords, end_coords)
    end
end

"""
 
Struct that defines movement of taxis during trip in simulation.

NOTE:
Currently not implemented into simulation, Move_taxi is.

"""
mutable struct Taxi_trip
    tID::Int64
    m0::Move # Position of taxi at start of trip
    m1::Move # Going to passenger
    m2::Move # Completing passenger trip
    m3::Move # Going to rank to idle
    m4::Union{Move,Nothing} # Position of taxi while waiting for next trip
    m5::Union{Move,Nothing} # Going to new passenger

    function Taxi_trip(tID)
        tID = tID
        m0 = Move(0.0, (0.0, 0.0), (0.0, 0.0))
        m1 = Move(0.0, (0.0, 0.0), (0.0, 0.0))
        m2 = Move(0.0, (0.0, 0.0), (0.0, 0.0))
        m3 = Move(0.0, (0.0, 0.0), (0.0, 0.0))
        m4 = nothing
        m5 = nothing
        return new(tID, m0, m1, m2, m3, m4, m5)
    end
end


"""

        Structure representing the graphical format of the network where DIST and TIME are 
        square matrices, where each entry represent the distance and time taken for going from 
        row_index to col_index for that entry. 
        
        TIME_REV is essentially the transpose of TIME matrix which means the time taken for going 
        from col_index to row_index.
"""
struct Network
    Lat::Vector{Float64}
    Long::Vector{Float64}
	DIST::SparseMatrixCSC{Float64,Int64}
    TIME::SparseMatrixCSC{Float64,Int64}
    TIME_REV::SparseMatrixCSC{Float64,Int64}

    function Network(Lat::Vector{Float64} ,Long::Vector{Float64} ,DIST::SparseMatrixCSC{Float64,Int64}, TIME::SparseMatrixCSC{Float64,Int64})
        return new(Lat, Long, DIST, TIME, copy(TIME'))
    end

end

"""

    Struct used for defining the initial location of all entities. This also keeps account of all the static 
    data of the simulation. All the inner variables are 1-D vectors where the index number is the rank_ID 
    (i.e. rID).

"""
struct Data
    num_ranks::Int64
    num_taxis::Int64
    rank_node::Vector{Int64}
    rank_popularity::Vector{Float64}
    rank_mode::Vector{Union{String,Nothing}}
    rank_capacity::Vector{Int64}
    rank_name::Vector{Any}
    rank_init_taxi::Vector{Any}

    function Data(num_ranks::Int64, num_taxis::Int64)
        rank_node = Vector{Int64}(undef, num_ranks)
        rank_popularity = Vector{Float64}(undef, num_ranks)
        rank_mode = Vector{Union{String,Nothing}}(undef, num_ranks)
        rank_capacity = Vector{Int64}(undef, num_ranks)
        rank_name = Vector{String}(undef, num_ranks)
        rank_init_taxi = Vector{Int64}(undef,num_ranks)
        return new(num_ranks, num_taxis, rank_node, rank_popularity, rank_mode, rank_capacity, rank_name, rank_init_taxi)
    end
end

struct Rank_status
    queue::Vector{Vector{Int64}}
    queue_taxi_soc::Vector{Vector{Float64}}
    plugin_charging::Vector{Vector{Int64}}
    plugin_charging_soc::Vector{Vector{Float64}}

    function Rank_status(num_ranks::Int64) 
        queue = [Vector{Int64}() for i = 1:num_ranks]
        queue_taxi_soc = [Vector{Float64}() for i = 1:num_ranks]
        plugin_charging = [Vector{Int64}() for i = 1:num_ranks]
        plugin_charging_soc = [Vector{Float64}() for i = 1:num_ranks]
        return new(queue,
                    queue_taxi_soc,
                    plugin_charging,
                    plugin_charging_soc)
    end
end


"""
        Status of various variables after every iteration. Here, all the variables are vectors
        of either num of taxis or number of ranks. The individual meaning are mentioned along with 
        the declarations.
"""
struct Status
    rank_volume::Vector{Int64}          # Total number of taxis present in the rank.
    rank_queue_electric::Vector{Vector{Int64}}      # The inner vector represents the queue with individual entries being the Taxi_id
    rank_queue_combustion::Vector{Vector{Int64}}    # The inner vector represents the queue with individual entries being the Taxi_id
    rank_chargers_plugin::Vector{Union{Resource,Nothing}}       # Simulation Resource - The number of charging points for that rank.
    rank_chargers_wireless::Vector{Union{Resource,Nothing}} # Simulation Resource - The number of charging points for that rank.
    taxi_loc::Vector{Union{Float64,Int64}}
    taxi_soc::Vector{Float64}
    taxi_trip::Vector{Trip}
    taxi_time_start_charging::Vector{Float64}
    taxi_in_service::Vector{Bool}
    taxi_origin::Vector{Int64}
    taxi_home_node::Vector{Int64}
    taxi_route_home::Vector{Union{Route,Nothing}}
    taxi_requesting_charger::Vector{Bool}
    taxi_start_covering::Vector{Float64}
    rank_num_wireless::Vector{Int64}
    rank_wireless_updated::Vector{Float64}
    rank_num_plugin::Vector{Int64}
    rank_plugin_updated::Vector{Float64}
    rank_status::Rank_status

    function Status(num_ranks::Int64, num_taxis::Int64)
        rank_volume = Vector{Int64}(undef, num_ranks)
        rank_queue_electric = [Vector{Int64}() for i = 1:num_ranks]
        rank_queue_combustion = [Vector{Int64}() for i = 1:num_ranks]
        rank_chargers_plugin = Vector{Union{Resource,Nothing}}(undef, num_ranks)
        rank_chargers_wireless = Vector{Union{Resource,Nothing}}(undef, num_ranks)
        taxi_loc = Vector{Union{Float64,Int64}}(undef, num_taxis)
        taxi_soc = Vector{Float64}(undef, num_taxis)
        taxi_trip = Vector{Trip}(undef, num_taxis)
        taxi_time_start_charging = ones(Float64, num_taxis) * Inf
        taxi_in_service = Vector{Bool}(undef,num_taxis)
        taxi_in_service = [taxi_in_service[i] = true for i in 1:num_taxis]
        taxi_origin = Vector{Int64}(undef, num_taxis)
        taxi_home_node = Vector{Int64}(undef, num_taxis)
        taxi_route_home = Vector{Union{Route,Nothing}}(undef, num_taxis)
        taxi_route_home = [taxi_route_home[i] = nothing for i in 1:num_taxis]
        taxi_requesting_charger = Vector{Bool}(undef, num_taxis)
        taxi_requesting_charger = [taxi_requesting_charger[i] = false for i in 1:num_taxis]
        taxi_start_covering = ones(Float64, num_taxis) * Inf
        rank_num_wireless = zeros(Int64, num_ranks)
        rank_wireless_updated = zeros(Float64, num_ranks)
        rank_num_plugin = zeros(Int64, num_ranks)
        rank_plugin_updated = zeros(Float64, num_ranks)
        rank_status = Rank_status(num_ranks)
        return new(rank_volume,
                   rank_queue_electric,
                   rank_queue_combustion,
                   rank_chargers_plugin,
                   rank_chargers_wireless,
                   taxi_loc,
                   taxi_soc,
                   taxi_trip, 
                   taxi_time_start_charging,
                   taxi_in_service,
                   taxi_origin,
                   taxi_home_node,
                   taxi_route_home,
                   taxi_requesting_charger,
                   taxi_start_covering,
                   rank_num_wireless,
                   rank_wireless_updated,
                   rank_num_plugin,
                   rank_plugin_updated,
                   rank_status)
    end
end

"""

    Structure used to log all the variables after every iteration.

"""
struct Log
    trip_taxi::Vector{Int64}
    rank_plugin_total_energy::Vector{Float64}
    rank_wireless_total_energy::Vector{Float64}
    taxi_route1_time::Vector{Vector{Float64}}
    taxi_route2_time::Vector{Vector{Float64}}
    taxi_route3_time::Vector{Vector{Float64}}
    taxi_route4_time::Vector{Vector{Float64}}
    taxi_route1_energy::Vector{Vector{Float64}}
    taxi_route2_energy::Vector{Vector{Float64}}
    taxi_route3_energy::Vector{Vector{Float64}}
    taxi_route4_energy::Vector{Vector{Float64}}
    taxi_route_home_energy::Vector{Vector{Float64}}
    taxi_ranks_visited::Vector{Vector{Int64}}
    taxi_plugin_waiting_time::Vector{Vector{Float64}}
    taxi_wireless_waiting_time::Vector{Vector{Float64}}
    taxi_queuing_time::Vector{Vector{Float64}}
    rank_urgent_wireless_waiting_time::Vector{Vector{Float64}}
    rank_wireless_waiting_time::Vector{Vector{Float64}}
    rank_plugin_waiting_time::Vector{Vector{Float64}}
    rank_wireless_usage::Vector{Vector{Float64}}
    rank_wireless_covering::Vector{Float64}
    rank_plugin_usage::Vector{Vector{Float64}}
    rank_status_trace::Vector{Rank_status}
    taxi_trip_trace::Vector{Taxi_trip}
    taxi_move_trace::Vector{Move_taxi}

    function Log(num_ranks::Int64, num_taxis::Int64, wireless_chargers::Array{Int64}, plugin_chargers::Array{Int64})
        trip_taxi = Vector{Int64}()
        rank_plugin_total_energy = zeros(Float64, num_ranks)
        rank_wireless_total_energy = zeros(Float64, num_ranks)
        taxi_route1_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route2_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route3_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route4_time = [Vector{Float64}() for i in 1:num_taxis]
        taxi_route1_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route2_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route3_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route4_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route_home_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_ranks_visited = [Vector{Int64}() for i in 1:num_taxis]
        taxi_plugin_waiting_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_wireless_waiting_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_queuing_time = [Vector{Float64}() for i = 1:num_taxis]
        rank_urgent_wireless_waiting_time = [Vector{Float64}() for i = 1:num_ranks]
        rank_wireless_waiting_time = [Vector{Float64}() for i = 1:num_ranks]
        rank_plugin_waiting_time = [Vector{Float64}() for i = 1:num_ranks]
        rank_wireless_usage = [zeros(Float64, wireless_chargers[i]+1) for i = 1:num_ranks]
        rank_wireless_covering = zeros(Float64, num_ranks)
        rank_plugin_usage = [zeros(Float64, plugin_chargers[i]+1) for i = 1:num_ranks]
        rank_status_trace = Vector{Rank_status}()
        taxi_trip_trace = Vector{Taxi_trip}()
        taxi_move_trace = Vector{Move_taxi}()
        return new(trip_taxi,
                   rank_plugin_total_energy,
                   rank_wireless_total_energy,
                   taxi_route1_time,
                   taxi_route2_time,
                   taxi_route3_time,
                   taxi_route4_time,
                   taxi_route1_energy,
                   taxi_route2_energy,
                   taxi_route3_energy,
                   taxi_route4_energy,
                   taxi_route_home_energy,
                   taxi_ranks_visited,
                   taxi_plugin_waiting_time,
                   taxi_wireless_waiting_time,
                   taxi_queuing_time,
                   rank_urgent_wireless_waiting_time,
                   rank_wireless_waiting_time,
                   rank_plugin_waiting_time,
                   rank_wireless_usage,
                   rank_wireless_covering,
                   rank_plugin_usage,
                   rank_status_trace,
                   taxi_trip_trace, 
                   taxi_move_trace)
    end
end

"""
DESCRIPTION OF taxi_move_trace
-------------------------------
A vector of Move_taxi structs. Contains every movement of a taxi during the simulation. A movement 
is defined as when a taxi goes from one node in the network to another. For more specifics see 
definiton of Move_taxi struct above.

The order of movements in taxi_move_trace is based on the time which the movement finishes.
e.g if there are two movements starting at 1.0 then the movement that finishes first will 
be first in the vector.

You might need to rearrange the order of the movements so that they are ordered based on 
when the movement starts. 

"""