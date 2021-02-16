struct Route
    time::Union{Float64,Vector{Float64}}
    energy::Union{Float64,Vector{Float64}}
    path::Vector{Int64}
end

mutable struct Trip
    wait::Float64
    route1::Union{Nothing,Route}
    route2::Route
    route3::Union{Nothing,Route}
    rID::Int64
    urgent::Bool
end

struct Network
    DIST::SparseMatrixCSC{Float64,Int64}
    TIME::SparseMatrixCSC{Float64,Int64}
    TIME_REV::SparseMatrixCSC{Float64,Int64}

    function Network(DIST::SparseMatrixCSC{Float64,Int64}, TIME::SparseMatrixCSC{Float64,Int64})
        return new(DIST, TIME, copy(TIME'))
    end
end

struct Data
    num_ranks::Int64
    num_taxis::Int64
    rank_node::Vector{Int64}
    rank_popularity::Vector{Float64}
    rank_mode::Vector{Union{String,Nothing}}

    function Data(num_ranks::Int64, num_taxis::Int64)
        rank_node = Vector{Int64}(undef, num_ranks)
        rank_popularity = Vector{Float64}(undef, num_ranks)
        rank_mode = Vector{Union{String,Nothing}}(undef, num_ranks)
        return new(num_ranks, num_taxis, rank_node, rank_popularity, rank_mode)
    end
end

struct Status
    rank_volume::Vector{Int64}
    rank_queue_electric::Vector{Vector{Int64}}
    rank_queue_combustion::Vector{Vector{Int64}}
    rank_chargers_plugin::Vector{Union{Resource,Nothing}}
    rank_chargers_wireless::Vector{Union{Resource,Nothing}}
    taxi_loc::Vector{Int64}
    taxi_soc::Vector{Float64}
    taxi_trip::Vector{Trip}
    taxi_time_start_charging::Vector{Float64}

    function Status(num_ranks::Int64, num_taxis::Int64)
        rank_volume = Vector{Int64}(undef, num_ranks)
        rank_queue_electric = [Vector{Int64}() for i = 1:num_ranks]
        rank_queue_combustion = [Vector{Int64}() for i = 1:num_ranks]
        rank_chargers_plugin = Vector{Union{Resource,Nothing}}(undef, num_ranks)
        rank_chargers_wireless = Vector{Union{Resource,Nothing}}(undef, num_ranks)
        taxi_loc = Vector{Int64}(undef, num_taxis)
        taxi_soc = Vector{Float64}(undef, num_taxis)
        taxi_trip = Vector{Trip}(undef, num_taxis)
        taxi_time_start_charging = ones(Float64, num_taxis) * Inf
        return new(rank_volume, rank_queue_electric, rank_queue_combustion, rank_chargers_plugin, rank_chargers_wireless, taxi_loc, taxi_soc, taxi_trip, taxi_time_start_charging)
    end
end

struct Log
    trip_taxi::Vector{Int64}
    rank_plugin_total_energy::Vector{Float64}
    rank_wireless_total_energy::Vector{Float64}
    taxi_route1_time::Vector{Vector{Float64}}
    taxi_route2_time::Vector{Vector{Float64}}
    taxi_route3_time::Vector{Vector{Float64}}
    taxi_route1_energy::Vector{Vector{Float64}}
    taxi_route2_energy::Vector{Vector{Float64}}
    taxi_route3_energy::Vector{Vector{Float64}}
    taxi_plugin_waiting_time::Vector{Vector{Float64}}
    taxi_wireless_waiting_time::Vector{Vector{Float64}}
    taxi_queuing_time::Vector{Vector{Float64}}

    function Log(num_ranks::Int64, num_taxis::Int64)
        trip_taxi = Vector{Int64}()
        rank_plugin_total_energy = zeros(Float64, num_ranks)
        rank_wireless_total_energy = zeros(Float64, num_ranks)
        taxi_route1_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route2_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route3_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route1_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route2_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_route3_energy = [Vector{Float64}() for i = 1:num_taxis]
        taxi_plugin_waiting_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_wireless_waiting_time = [Vector{Float64}() for i = 1:num_taxis]
        taxi_queuing_time = [Vector{Float64}() for i = 1:num_taxis]
        return new(trip_taxi,
                   rank_plugin_total_energy,
                   rank_wireless_total_energy,
                   taxi_route1_time,
                   taxi_route2_time,
                   taxi_route3_time,
                   taxi_route1_energy,
                   taxi_route2_energy,
                   taxi_route3_energy,
                   taxi_plugin_waiting_time,
                   taxi_wireless_waiting_time,
                   taxi_queuing_time)
    end
end
