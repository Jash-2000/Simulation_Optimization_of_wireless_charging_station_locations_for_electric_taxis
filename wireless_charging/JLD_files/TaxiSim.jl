using CSV
using DataFrames
using Dates
using JLD
using Parameters
using ResumableFunctions
using SimJulia
using SparseArrays

include("types.jl")
include("data.jl")
include("energy.jl")
include("routing.jl")

@resumable function taxi(sim::Simulation, net::Network, data::Data, status::Status, log::Log, tID::Int64)
    queue = isinf(status.taxi_soc[tID]) ? status.rank_queue_combustion : status.rank_queue_electric

    try
        # initial idle before first dispatch
        @yield timeout(sim, Inf)
    finally
        while true
            rID = status.taxi_loc[tID]

            # if current location is a rank, leave the queue at the rank
            if rID > 0
                filter!(t -> t != tID, queue[rID])
                status.rank_volume[rID] -= 1
            end

            status.taxi_loc[tID] = 0
            trip = status.taxi_trip[tID]

            if isnothing(trip.route1)
                # call source is a rank -> route1 is null
                push!(log.taxi_route1_time[tID], 0.0)
                push!(log.taxi_route1_energy[tID], 0.0)
            else
                # call source is not a rank -> route1 is travel to call source
                @yield timeout(sim, trip.route1.time)
                status.taxi_soc[tID] -= trip.route1.energy
                push!(log.taxi_route1_time[tID], trip.route1.time)
                push!(log.taxi_route1_energy[tID], trip.route1.energy)
            end

            # travel from call source to call target
            @yield timeout(sim, trip.route2.time)
            status.taxi_soc[tID] -= trip.route2.energy
            push!(log.taxi_route2_time[tID], trip.route2.time)
            push!(log.taxi_route2_energy[tID], trip.route2.energy)

            if isnothing(trip.route3)
                # call target is a rank -> stay there
                push!(log.taxi_route3_time[tID], 0.0)
                push!(log.taxi_route3_energy[tID], 0.0)
            else
                if trip.urgent
                    # if low soc, travel to nearest rank with charger
                    @yield timeout(sim, trip.route3.time)
                    status.taxi_soc[tID] -= trip.route3.energy
                    push!(log.taxi_route3_time[tID], trip.route3.time)
                    push!(log.taxi_route3_energy[tID], trip.route3.energy)
                else
                    # otherwise, travel to nearby rank with drive disruption enabled
                    status.taxi_loc[tID] = -trip.route3.path[1]
                    flag = false
                    route3_time = 0.0
                    route3_energy = 0.0

                    for i = 1:length(trip.route3.time)
                        try
                            @yield timeout(sim, trip.route3.time[i])
                        catch
                            flag = true
                            break
                        end

                        status.taxi_loc[tID] = -trip.route3.path[i+1]
                        status.taxi_soc[tID] -= trip.route3.energy[i]
                        route3_time += trip.route3.time[i]
                        route3_energy += trip.route3.energy[i]
                    end

                    push!(log.taxi_route3_time[tID], route3_time)
                    push!(log.taxi_route3_energy[tID], route3_energy)

                    if flag
                        # restarts loop to send taxi to call source
                        continue
                    end
                end
            end

            # update location with current rank ID
            rID = trip.rID
            status.rank_volume[rID] += 1
            mode = data.rank_mode[rID]

            if trip.urgent
                if (mode == "plugin") || (mode == "mixed")
                    # if there are plugin chargers, do plugin charging before joining queue
                    timew = now(sim)
                    @yield request(status.rank_chargers_plugin[rID])
                    push!(log.taxi_plugin_waiting_time[tID], now(sim) - timew)
                    soc = status.taxi_soc[tID]
                    @yield timeout(sim, nonlinear_charging_time(MODEL_PLUGIN, 1.0, soc, SOC_END_PLUGIN))
                    release(status.rank_chargers_plugin[rID])
                    log.rank_plugin_total_energy[rID] += SOC_END_PLUGIN - soc
                    status.taxi_soc[tID] = SOC_END_PLUGIN
                    push!(queue[rID], tID)
                    status.taxi_loc[tID] = rID
                    timeq = now(sim)

                    if mode == "mixed"
                        # if there are also wireless chargers, charge while queuing
                        try
                            @yield request(status.rank_chargers_wireless[rID])
                            status.taxi_time_start_charging[tID] = now(sim)
                            soc = status.taxi_soc[tID]
                            @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC_100))
                            log.rank_wireless_total_energy[rID] += SOC_100 - soc
                            status.taxi_soc[tID] = SOC_100
                            status.taxi_time_start_charging[tID] = Inf
                            @yield timeout(sim, Inf)
                        catch
                            release(status.rank_chargers_wireless[rID])
                            status.taxi_time_start_charging[tID] = Inf
                            push!(log.taxi_queuing_time[tID], now(sim) - timeq)
                            continue
                        end
                    else
                        # otherwise, just queue without charging
                        try
                            @yield timeout(sim, Inf)
                        catch
                            push!(log.taxi_queuing_time[tID], now(sim) - timeq)
                            continue
                        end
                    end
                else
                    # if there are only wireless chargers, join queue and charge
                    push!(queue[rID], tID)
                    timeq = now(sim)
                    @yield request(status.rank_chargers_wireless[rID])
                    push!(log.taxi_wireless_waiting_time[tID], now(sim) - timeq)
                    soc = status.taxi_soc[tID]
                    @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC_30))
                    log.rank_wireless_total_energy[rID] += SOC_30 - soc
                    status.taxi_soc[tID] = SOC_30
                    status.taxi_loc[tID] = rID

                    try
                        status.taxi_time_start_charging[tID] = now(sim)
                        soc = status.taxi_soc[tID]
                        @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC_100))
                        log.rank_wireless_total_energy[rID] += SOC_100 - soc
                        status.taxi_soc[tID] = SOC_100
                        status.taxi_time_start_charging[tID] = Inf
                        @yield timeout(sim, Inf)
                    catch
                        release(status.rank_chargers_wireless[rID])
                        status.taxi_time_start_charging[tID] = Inf
                        push!(log.taxi_queuing_time[tID], now(sim) - timeq)
                        continue
                    end
                end
            else
                # no need to charge -> just join queue and pick up charge if there are wireless chargers
                push!(queue[rID], tID)
                status.taxi_loc[tID] = rID
                timeq = now(sim)

                if (mode == "wireless") || (mode == "mixed")
                    try
                        @yield request(status.rank_chargers_wireless[rID])
                        status.taxi_time_start_charging[tID] = now(sim)
                        soc = status.taxi_soc[tID]
                        @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC_100))
                        log.rank_wireless_total_energy[rID] += SOC_100 - soc
                        status.taxi_soc[tID] = SOC_100
                        status.taxi_time_start_charging[tID] = Inf
                        @yield timeout(sim, Inf)
                    catch
                        release(status.rank_chargers_wireless[rID])
                        status.taxi_time_start_charging[tID] = Inf
                        push!(log.taxi_queuing_time[tID], now(sim) - timeq)
                        continue
                    end
                else
                    try
                        @yield timeout(sim, Inf)
                    catch
                        push!(log.taxi_queuing_time[tID], now(sim) - timeq)
                        continue
                    end
                end
            end
        end
    end
end

@resumable function dispatcher(sim::Simulation, net::Network, trips::Vector{Trip}, data::Data, status::Status, log::Log)
    taxis = [@process taxi(sim, net, data, status, log, tID) for tID in 1:data.num_taxis]

    num_trips = length(trips)
    node_rank = Dict{Int64,Int64}(data.rank_node[rID] => rID for rID in 1:data.num_ranks)
    rIDc = [rID for rID in 1:data.num_ranks if !isnothing(data.rank_mode[rID])]
    rIDc_node = data.rank_node[rIDc]

    for i = 1:num_trips
        trip = trips[i]
        @yield timeout(sim, trip.wait)

        # update soc of all taxis currently wirelessly charging
        for t = 1:data.num_taxis
            if !isinf(status.taxi_time_start_charging[t])
                soc = status.taxi_soc[t]
                status.taxi_soc[t] = nonlinear_charging(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, now(sim) - status.taxi_time_start_charging[t])
                log.rank_wireless_total_energy[status.taxi_loc[t]] += status.taxi_soc[t] - soc
                status.taxi_time_start_charging[t] = now(sim)
            end
        end

        # calculate minimum soc required for this trip
        soc_req = trip.route2.energy + (isnothing(trip.route3) ? 0 : trip.route3.energy)

        source = trip.route2.path[1]
        target = trip.route2.path[end]
        rIDs = haskey(node_rank, source) ? node_rank[source] : nothing
        tID = nothing

        # if the call source is a rank, ...
        if !isnothing(rIDs)
            # ... get first queued e-taxi at the rank with sufficient soc
            for t in status.rank_queue_electric[rIDs]
                if !iszero(status.taxi_loc[t]) & (status.taxi_soc[t] > soc_req)
                    tID = t
                    soc_end = status.taxi_soc[t] - soc_req
                    break
                end
            end

            # if there are no queued e-taxis with sufficient soc, get first queued ICE taxi at the rank
            if !isempty(status.rank_queue_combustion[rIDs])
                tID = status.rank_queue_combustion[rIDs][1]
                soc_end = Inf
            end
        end

        # if the call source is not a rank, or is a rank but no queued e-taxi nor ICE taxi with sufficient soc, ...
        if isnothing(tID)
            tIDa = Vector{Int64}()

            # ... look to all other ranks
            for r = 1:data.num_ranks
                if r != rIDs
                    # for each rank, identify all queued e-taxis with sufficient soc as well as ...
                    for t in status.rank_queue_electric[r]
                        if !iszero(status.taxi_loc[t]) & (status.taxi_soc[t] > soc_req)
                            push!(tIDa, t)
                        end
                    end

                    # ... the first queued ICE taxi
                    if !isempty(status.rank_queue_combustion[r])
                        push!(tIDa, status.rank_queue_combustion[r][1])
                    end
                end
            end

            # also identify all vacant driving taxis with sufficient soc
            for t = 1:data.num_taxis
                if (status.taxi_loc[t] < 0) & (status.taxi_soc[t] > soc_req)
                    push!(tIDa, t)
                end
            end

            # if there is at least one available taxi, ...
            if !isempty(tIDa)
                # ... compute route from all available taxis to source
                tIDa_node = [l > 0 ? data.rank_node[l] : l * -1 for l in status.taxi_loc[tIDa]]
                tIDa_tol = status.taxi_soc[tIDa] .- soc_req
                ind, trip.route1 = dijkstra_nearest_taxi_to_source(net, tIDa_node, source, tIDa_tol ./ ENERGY_PER_DISTANCE)

                # select the taxi that is nearest to the source and has enough soc to make the trip
                if !isnothing(ind)
                    tID = tIDa[ind]
                    soc_end = tIDa_tol[ind] - trip.route1.energy
                end
            end
        end

        if isnothing(tID)
            push!(log.trip_taxi, 0)
        else
            push!(log.trip_taxi, tID)

            # if the selected taxi will have high soc upon reaching call target, ...
            if soc_end > SOC_60
                trip.urgent = false

                # ... compute route from call target to nearby rank (instead of going straight to nearest rank with charger)
                prob = data.rank_popularity ./ (status.rank_volume .+ 1)
                prob /= sum(prob)
                temp_rID, temp_route3 = dijkstra_taxi_to_nearby_rank(net, target, data.rank_node, prob)
                soc_end = status.taxi_soc[tID] - (isnothing(trip.route1) ? 0.0 : trip.route1.energy) - trip.route2.energy - sum(temp_route3.energy)

                # drive to the nearby rank if it has chargers or soc upon reaching this rank will be > 30%
                if !isnothing(data.rank_mode[temp_rID]) | (soc_end > SOC_30)
                    trip.route3 = temp_route3
                    trip.rID = temp_rID
                end
            end

            # dispatch the taxi
            status.taxi_trip[tID] = trip
            println(i, "/", num_trips)
            interrupt(taxis[tID])
        end
    end
end
