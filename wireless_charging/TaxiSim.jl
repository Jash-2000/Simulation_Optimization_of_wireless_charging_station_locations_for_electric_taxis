using CSV
using DataFrames
using Dates
using JLD2
using FileIO
using Parameters
using ResumableFunctions
using SimJulia
using SparseArrays
using DelimitedFiles

include("types.jl")
include("data.jl")
include("energy.jl")
include("routing.jl")

@resumable function taxi(sim::Simulation, net::Network, data::Data, status::Status, log::Log, tID::Int64)
    # select queue that taxi joins at rank
    if !ONE_QUEUE
        queue = isinf(status.taxi_soc[tID]) ? status.rank_queue_combustion : status.rank_queue_electric
    else
        queue = status.rank_queue_electric
    end

    while true
        # if taxi is not in service...
        if !status.taxi_in_service[tID]
            # if taxi has not yet been in service or finished shift while urgent charging remove from rank queue
            if (0<status.taxi_loc[tID]<=NUM_NEARBY_RANKS)
                rID = status.taxi_loc[tID]
                filter!(t->t != tID, queue[rID])
                status.rank_volume[rID] -= 1
            end
            status.taxi_loc[tID] = Inf

            # ....return home and wait for next shift to start
            try 
                # complete journey home
                if !isnothing(status.taxi_route_home[tID])
                    taxi_move = generate_taxi_move(sim, net, status.taxi_route_home[tID], tID, nothing) # FIX time
                    push!(log.taxi_move_trace, deepcopy(taxi_move))
                    status.taxi_soc[tID] -= status.taxi_route_home[tID].energy
                    push!(log.taxi_route_home_energy[tID], status.taxi_route_home[tID].energy)
                end
                println("Waiting for next shift, ",tID)
                @yield timeout(sim, Inf)
            catch
                rID = status.taxi_origin[tID]
                push!(queue[rID],tID)
                status.rank_volume[rID] += 1
                status.taxi_loc[tID] = rID
                if !isinf(status.taxi_soc[tID])
                    # status.taxi_soc[tID] = SOC(100) # when uncommented taxis return from shift with full charge
                end
            end 
        end
        
        # Initial idle before first dispatch (taxis with wireless charging need to request chargers)
        rID = status.taxi_loc[tID]   
        mode = data.rank_mode[rID]
        taxi_move = Move_taxi(tID, now(sim), now(sim),rank_location(net, data, rID), rank_location(net, data, rID))
        push!(log.taxi_move_trace, deepcopy(taxi_move))
        if (mode == "wireless" || mode == "mixed") && !isinf(status.taxi_soc[tID])
            try
                status.taxi_requesting_charger[tID] = true
                timer = now(sim)
                @yield request(status.rank_chargers_wireless[rID])
                push!(log.rank_wireless_waiting_time[rID], now(sim) - timer)
                status.rank_num_wireless[rID] += 1
                status.taxi_requesting_charger[tID] = false
                if ELECTRIC_FIRST && ONE_QUEUE
                    update_queue(rID,tID,status)
                end
                status.taxi_time_start_charging[tID] = now(sim)
                soc = status.taxi_soc[tID]
                @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS,EFFICIENCY_WIRELESS,soc,SOC(100))) # _STATE_ goto error 
                log.rank_wireless_total_energy[rID] += SOC(100) - status.taxi_soc[tID]
                status.taxi_soc[tID] = SOC(100)
                status.taxi_time_start_charging[tID] = Inf
                status.taxi_start_covering[tID] = now(sim)
                @yield timeout(sim, Inf)
            catch
                release(status.rank_chargers_wireless[rID])
                update_charger_usage(sim, status,log,rID, "w")
                if !isinf(status.taxi_start_covering[tID])
                    log.rank_wireless_covering[rID] += (now(sim) - status.taxi_start_covering[tID])
                    status.taxi_start_covering[tID] = Inf
                end
                status.taxi_time_start_charging[tID] = Inf
                if !status.taxi_in_service[tID]
                    filter!(t -> t != tID, queue[rID])
                    status.rank_volume[rID] -= 1
                    continue
                end
            end
        else 
            try
                @yield timeout(sim, Inf)
            catch
                if !status.taxi_in_service[tID]
                    filter!(t -> t != tID, queue[rID])
                    status.rank_volume[rID] -= 1
                    continue
                end
            end
        end

        while true
            if status.taxi_in_service[tID]
                rID = status.taxi_loc[tID]
            end
            
            # if current location is a rank, leave the queue at the rank
            if rID > 0
                filter!(t -> t != tID, queue[rID])
                status.rank_volume[rID] -= 1
            end

            # check that taxi is still in service
            if !status.taxi_in_service[tID]
                break
            end   

            # set taxi to in service and get trip
            status.taxi_loc[tID] = 0
            trip = status.taxi_trip[tID]

            if isnothing(trip.route1)
                # call source is a rank -> route1 is null
                push!(log.taxi_route1_time[tID], 0.0)
                push!(log.taxi_route1_energy[tID], 0.0)
            else
                # call source is not a rank -> route1 is travel to call source
                @yield timeout(sim, trip.route1.time)
                taxi_move = generate_taxi_move(sim, net, trip.route1, tID, nothing)
                push!(log.taxi_move_trace, deepcopy(taxi_move))
                status.taxi_soc[tID] -= trip.route1.energy
                push!(log.taxi_route1_time[tID], trip.route1.time)
                push!(log.taxi_route1_energy[tID], trip.route1.energy)
            end

            # travel from call source to call target
            @yield timeout(sim, trip.route2.time)
            taxi_move = generate_taxi_move(sim, net, trip.route2, tID, nothing)
            push!(log.taxi_move_trace, deepcopy(taxi_move))
            status.taxi_soc[tID] -= trip.route2.energy
            push!(log.taxi_route2_time[tID], trip.route2.time)
            push!(log.taxi_route2_energy[tID], trip.route2.energy)

            # check that taxi is still in service
            if !status.taxi_in_service[tID]
                push!(log.taxi_route3_time[tID], 0.0)    
                push!(log.taxi_route3_energy[tID], 0.0)
                push!(log.taxi_route4_time[tID], 0.0)    
                push!(log.taxi_route4_energy[tID], 0.0)
                s = trip.route2.path[length(trip.route2.path)]
                status.taxi_route_home[tID] = dijkstra(net, s, status.taxi_home_node[tID])
                break
            end

            if isnothing(trip.route3)
                # call target is a rank -> stay there
                push!(log.taxi_route3_time[tID], 0.0)
                push!(log.taxi_route3_energy[tID], 0.0)
            else
                if trip.urgent
                    # if low soc, travel to nearest rank with charger that has capacity
                    rID = trip.rID
                    if status.rank_volume[rID] == data.rank_capacity[rID] 
                        # find route to nearest rank with capacity if nearest rank with charger is full
                        rIDc = [rID for rID in 1:data.num_ranks if status.rank_volume[rID]<data.rank_capacity[rID] && !isnothing(data.rank_mode[rID])]
                        rIDc_node = data.rank_node[rIDc]
                        s = trip.route3.path[1]
                        ind, new_route3 = dijkstra_taxi_to_nearest_charger(net,s,rIDc_node)
                        trip.route3 = new_route3
                        trip.rID = rIDc[ind]
                    end
                    # travel to nearest rank with charger that has capacity
                    @yield timeout(sim, trip.route3.time)
                    taxi_move = generate_taxi_move(sim, net, trip.route3, tID, nothing)
                    push!(log.taxi_move_trace, deepcopy(taxi_move))
                    status.taxi_soc[tID] -= trip.route3.energy
                    push!(log.taxi_route3_time[tID], trip.route3.time)
                    push!(log.taxi_route3_energy[tID], trip.route3.energy)
                else
                    # otherwise, travel to nearby rank that has capacity with drive disruption enabled
                    # check nearby rank has capacity
                    rID = trip.rID
                    if status.rank_volume[rID] == data.rank_capacity[rID] 
                        # find route to nearby rank with capacity
                        rIDcap = [rID for rID in 1:data.num_ranks if status.rank_volume[rID]<data.rank_capacity[rID]]
                        rIDcap_node = data.rank_node[rIDcap]
                        prob = data.rank_popularity[rIDcap] ./ (status.rank_volume[rIDcap] .+1)
                        prob /= sum(prob)
                        s = trip.route3.path[1]
                        ind, new_route3 = dijkstra_taxi_to_nearby_rank(net,s,rIDcap_node,prob)
                        trip.route3  = new_route3
                        trip.rID = rIDcap[ind]
                    end
                    # travel to nearby rank with drive disruption enabled
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
                    if length(trip.route3.time) > 0 # CHECK WHY some ROUTE 3 had no time and only one element in path??
                        taxi_move = generate_taxi_move(sim, net, trip.route3, tID, i)
                        push!(log.taxi_move_trace, deepcopy(taxi_move))
                    end
                    push!(log.taxi_route3_time[tID], route3_time)
                    push!(log.taxi_route3_energy[tID], route3_energy)

                    if flag
                        # restarts loop to send taxi to call source
                        push!(log.taxi_route4_time[tID],0.0)
                        push!(log.taxi_route4_energy[tID],0.0)
                        continue 
                    end
                end
            end

            # check taxi is still in service
            if !status.taxi_in_service[tID]
                status.taxi_route_home[tID] = dijkstra(net, data.rank_node[trip.rID], status.taxi_home_node[tID])
                break
            end

            rID = trip.rID
            # Check if destination rank has capacity for extra taxi
            if status.rank_volume[rID] == data.rank_capacity[rID]
                route4_time = 0.0
                route4_energy = 0.0
                ranks_vistied = 1
                new_rID = rID
                while true
                    if trip.urgent
                        # find nearest charger
                        rIDc = [rID for rID in 1:data.num_ranks if status.rank_volume[rID]<data.rank_capacity[rID] && !isnothing(data.rank_mode[rID])]
                        rIDc_node = data.rank_node[rIDc]
                        ind, new_route = dijkstra_taxi_to_nearest_charger(net, data.rank_node[new_rID], rIDc_node)

                        # travel to nearest charger
                        @yield timeout(sim, new_route.time)
                        taxi_move = generate_taxi_move(sim, net, new_route, tID, nothing)
                        push!(log.taxi_move_trace, deepcopy(taxi_move))
                        status.taxi_soc[tID] -= new_route.energy
                        route4_time += new_route.time
                        route4_energy += new_route.energy
                        new_rID = rIDc[ind]
                        
                        disrupted = false
                    else
                        # find nearby rank
                        rIDs = [rID for rID in 1:data.num_ranks if status.rank_volume[rID]<data.rank_capacity[rID]]
                        rNODES = data.rank_node[rIDs]
                        prob = data.rank_popularity[rIDs] ./ (status.rank_volume[rIDs] .+ 1)
                        prob /= sum(prob)
                        ind, new_route = dijkstra_taxi_to_nearby_rank(net, data.rank_node[new_rID], rNODES, prob)

                        # travel to nearby rank with disruption enabled
                        status.taxi_loc[tID] = -new_route.path[1]
                        flag  = false
                        disrupted = false
                        for i in 1:length(new_route.time)
                            try
                                @yield timeout(sim, new_route.time[i])
                            catch
                                flag = true
                                disrupted = true
                                break
                            end
                            status.taxi_loc[tID] = -new_route.path[i+1] 
                            status.taxi_soc[tID] -= new_route.energy[i]
                            route4_time += new_route.time[i]
                            route4_energy += new_route.energy[i]
                        end
                        taxi_move = generate_taxi_move(sim, net, new_route, tID, i)
                        push!(log.taxi_move_trace, taxi_move)
                        new_rID = rIDs[ind]
                    end

                    if !disrupted
                        ranks_vistied += 1
                    end

                    # if found rank with capacity or taxi has new dispatch continue taxi operation
                    if disrupted || status.rank_volume[new_rID]<data.rank_capacity[new_rID]
                        push!(log.taxi_route4_time[tID], route4_time)
                        push!(log.taxi_route4_energy[tID], route4_energy)
                        push!(log.taxi_ranks_visited[tID],ranks_vistied)
                        break
                    end
                    if status.taxi_soc[tID] < SOC(60)
                        trip.urgent = true
                    end
                end

                if disrupted
                    # restarts loop to send taxi to call source
                    continue
                else
                    # update rank with new rank ID
                    rID = new_rID
                end
            else
                push!(log.taxi_route4_time[tID], 0.0)
                push!(log.taxi_route4_energy[tID],0.0)
                push!(log.taxi_ranks_visited[tID],1)
            end

            # check taxi is still in service
            if !status.taxi_in_service[tID]
                status.taxi_route_home[tID] = dijkstra(net, data.rank_node[rID], status.taxi_home_node[tID])
                break
            end

            # update location with current rank ID
            mode = data.rank_mode[rID]

            if trip.urgent
                if (mode == "plugin") || (mode == "mixed")
                    # if there are plugin chargers, do plugin charging before joining queue
                    timew = now(sim)
                    push!(status.rank_status.plugin_charging[rID], tID)
                    @yield request(status.rank_chargers_plugin[rID])
                    status.rank_num_plugin[rID] += 1
                    push!(log.taxi_plugin_waiting_time[tID], now(sim) - timew)
                    push!(log.rank_plugin_waiting_time[rID], now(sim) - timew)
                    soc = status.taxi_soc[tID]
                    @yield timeout(sim, nonlinear_charging_time(MODEL_PLUGIN, 1.0, soc, SOC_END_PLUGIN))
                    release(status.rank_chargers_plugin[rID])
                    update_charger_usage(sim, status, log, rID, "p")
                    log.rank_plugin_total_energy[rID] += SOC_END_PLUGIN - soc
                    status.taxi_soc[tID] = SOC_END_PLUGIN
                    filter!(t -> t != tID, status.rank_status.plugin_charging[rID])
                    push!(queue[rID], tID)
                    status.rank_volume[rID] += 1
                    status.taxi_loc[tID] = rID
                    timeq = now(sim)
                    # check taxi is still in service
                    if !status.taxi_in_service[tID]
                        push!(log.taxi_queuing_time[tID], 0.0) 
                        status.taxi_route_home[tID] = dijkstra(net, data.rank_node[rID], status.taxi_home_node[tID])
                        break 
                    end

                    if mode == "mixed"
                        # if there are also wireless chargers, charge while queuing
                        try
                            status.taxi_requesting_charger[tID] = true
                            @yield request(status.rank_chargers_wireless[rID])
                            push!(log.rank_wireless_waiting_time[rID], now(sim) - timeq)
                            status.rank_num_wireless[rID] += 1
                            status.taxi_requesting_charger[tID] = false
                            if ELECTRIC_FIRST && ONE_QUEUE
                                update_queue(rID,tID,status)
                            end 
                            status.taxi_time_start_charging[tID] = now(sim)
                            soc = status.taxi_soc[tID]
                            @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC(100)))
                            log.rank_wireless_total_energy[rID] += SOC(100) - status.taxi_soc[tID]
                            status.taxi_soc[tID] = SOC(100)
                            status.taxi_time_start_charging[tID] = Inf
                            status.taxi_start_covering[tID] = now(sim)
                            @yield timeout(sim, Inf)
                        catch
                            release(status.rank_chargers_wireless[rID])
                            update_charger_usage(sim, status, log, rID, "w")
                            if !isinf(status.taxi_start_covering[tID])
                                log.rank_wireless_covering[rID] += (now(sim) - status.taxi_start_covering[tID])
                                status.taxi_start_covering[tID] = Inf
                            end
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
                    status.rank_volume[rID] += 1
                    timeq = now(sim)
                    status.taxi_requesting_charger[tID] = true
                    status.taxi_loc[tID] = rID
                    @yield request(status.rank_chargers_wireless[rID])
                    push!(log.rank_urgent_wireless_waiting_time[rID], now(sim) - timeq)
                    status.rank_num_wireless[rID] += 1
                    if ELECTRIC_FIRST && ONE_QUEUE
                        update_queue(rID,tID,status)
                    end
                    push!(log.taxi_wireless_waiting_time[tID], now(sim) - timeq)
                    soc = status.taxi_soc[tID]
                    @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC(30)))
                    log.rank_wireless_total_energy[rID] += SOC(30) - soc
                    status.taxi_soc[tID] = SOC(30)
                    status.taxi_requesting_charger[tID] = false
                    # check taxi is still in service
                    if !status.taxi_in_service[tID]
                        push!(log.taxi_queuing_time[tID], 0.0)
                        release(status.rank_chargers_wireless[rID])
                        update_charger_usage(sim, status, log, rID, "w")
                        break
                    end

                    try
                        status.taxi_time_start_charging[tID] = now(sim)
                        soc = status.taxi_soc[tID]
                        @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC(100)))
                        log.rank_wireless_total_energy[rID] += SOC(100) - status.taxi_soc[tID]
                        status.taxi_soc[tID] = SOC(100)
                        status.taxi_time_start_charging[tID] = Inf
                        status.taxi_start_covering[tID] = now(sim)
                        @yield timeout(sim, Inf)
                    catch
                        release(status.rank_chargers_wireless[rID])
                        update_charger_usage(sim, status, log, rID, "w")
                        if !isinf(status.taxi_start_covering[tID])
                            log.rank_wireless_covering[rID] += (now(sim) - status.taxi_start_covering[tID])
                            status.taxi_start_covering[tID] = Inf
                        end
                        status.taxi_time_start_charging[tID] = Inf
                        push!(log.taxi_queuing_time[tID], now(sim) - timeq)
                        continue
                    end
                end
            elseif !isinf(status.taxi_soc[tID])
                # for electric taxis, no need to charge -> just join queue and pick up charge if there are wireless chargers
                push!(queue[rID], tID)
                status.rank_volume[rID] += 1
                status.taxi_loc[tID] = rID
                timeq = now(sim)
                if (mode == "wireless") || (mode == "mixed")
                    try
                        status.taxi_requesting_charger[tID] = true
                        @yield request(status.rank_chargers_wireless[rID])
                        push!(log.rank_wireless_waiting_time[rID], now(sim) - timeq)
                        status.rank_num_wireless[rID] += 1
                        status.taxi_requesting_charger[tID] = false
                        if ELECTRIC_FIRST && ONE_QUEUE
                            update_queue(rID,tID,status)
                        end
                        status.taxi_time_start_charging[tID] = now(sim)
                        soc = status.taxi_soc[tID]
                        @yield timeout(sim, nonlinear_charging_time(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, SOC_nominal))
                        log.rank_wireless_total_energy[rID] += SOC_nominal - status.taxi_soc[tID]
                        status.taxi_soc[tID] = SOC_nominal
                        status.taxi_time_start_charging[tID] = Inf
                        status.taxi_start_covering[tID] = now(sim)
                        @yield timeout(sim, Inf)
                    catch
                        release(status.rank_chargers_wireless[rID])
                        update_charger_usage(sim, status, log, rID, "w")
                        if !isinf(status.taxi_start_covering[tID])
                            log.rank_wireless_covering[rID] += (now(sim) - status.taxi_start_covering[tID])
                            status.taxi_start_covering[tID] = Inf
                        end
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
            else 
                # the taxi has combustion engine therefore doesn't need to charge
                push!(queue[rID],tID)
                status.rank_volume[rID] += 1
                status.taxi_loc[tID] = rID
                timeq = now(sim)
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


@resumable function dispatcher(sim::Simulation, net::Network, trips::Vector{Trip}, data::Data, status::Status, log::Log, shifts::Array{Bool}, animSpeed::Int64 = 0)
    taxis = [@process taxi(sim, net, data, status, log, tID) for tID in 1:data.num_taxis]

    # initialise taxis starting with wireless charging (get them to idle with chargers)
    @yield timeout(sim,0.0)
    @yield timeout(sim,0.0)
    update_rank_status(status)
    push!(log.rank_status_trace, deepcopy(status.rank_status)) # add initial rank status to trace

    num_trips = length(trips)
    node_rank = Dict{Int64,Int64}(data.rank_node[rID] => rID for rID in 1:data.num_ranks)
    rIDc = [rID for rID in 1:data.num_ranks if !isnothing(data.rank_mode[rID])]
    rIDc_node = data.rank_node[rIDc]

    active_trips = Trip[]
    tripIDX = 1
    animation_speed = animSpeed

    while (animation_speed >= 0 )
        # Add new trip requests to active_trips
        while now(sim) >= trips[tripIDX].time
            push!(active_trips, trips[tripIDX])
            println(tripIDX, "/", num_trips)
            tripIDX += 1
            if tripIDX == length(trips)+1
                break
            end
        end

        # update which taxis are in service
        in_service(sim,status,shifts)

        # interrupt taxis that are idling at rank and have finished shift
        for r in 1:NUM_NEARBY_RANKS
            if !ONE_QUEUE
                queue = cat(copy(status.rank_queue_electric[r]), copy(status.rank_queue_combustion[r]), dims=1)
            else
                queue = copy(status.rank_queue_electric[r])
            end
            for t in queue 
                if !status.taxi_in_service[t] & !status.taxi_requesting_charger[t]
                    #println("The queue before, ", queue)
                    println("Interrupting taxi (end shift from rank (queue)), tID: ", t)
                    status.taxi_route_home[t] = dijkstra(net, data.rank_node[r], status.taxi_home_node[t])
                    status.taxi_loc[t] = Inf
                    interrupt(taxis[t])
                    @yield timeout(sim, 0.0)
                end
            end
        end

        # interrupt taxis that are waiting for shift and need to begin shift
        for tID = 1:data.num_taxis
            if (isinf(status.taxi_loc[tID])) & status.taxi_in_service[tID]
                status.taxi_loc[tID] = status.taxi_origin[tID]
                println("Interrupting taxi (to start shift), tID: ", tID)
                interrupt(taxis[tID])
                @yield timeout(sim, 0.0)
            end
        end

        # update soc of all taxis currently wirelessly charging
        for t = 1:data.num_taxis
            if !isinf(status.taxi_time_start_charging[t]) & status.taxi_in_service[t]
                soc = status.taxi_soc[t]
                status.taxi_soc[t] = nonlinear_charging(MODEL_WIRELESS, EFFICIENCY_WIRELESS, soc, now(sim) - status.taxi_time_start_charging[t])
                log.rank_wireless_total_energy[status.taxi_loc[t]] += status.taxi_soc[t] - soc
                status.taxi_time_start_charging[t] = now(sim)
            end
        end

        completed = Int64[] # indices of trips in active_trips that have been completed
        for j in 1:length(active_trips)
            trip = active_trips[j]

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
                    if !iszero(status.taxi_loc[t]) & (status.taxi_soc[t]-SOC_MIN > soc_req) & (status.taxi_in_service[t]) & !status.taxi_requesting_charger[t]
                        tID = t
                        soc_end = status.taxi_soc[t] - soc_req
                        break
                    end
                end

                # if there are no queued e-taxis with sufficient soc, get first queued ICE taxi at the rank
                if !isempty(status.rank_queue_combustion[rIDs]) & isnothing(tID)
                    for t in status.rank_queue_combustion[rIDs]
                        if status.taxi_in_service[t]
                            tID = t
                            soc_end = Inf
                            break
                        end
                    end
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
                            if !iszero(status.taxi_loc[t]) & (status.taxi_soc[t]-SOC_MIN > soc_req) & !isinf(status.taxi_loc[t]) & !status.taxi_requesting_charger[t]
                                push!(tIDa, t)
                                break
                            end
                        end

                        # ... the first queued ICE taxi
                        if !isempty(status.rank_queue_combustion[r])
                            for t in status.rank_queue_combustion[r]
                                if status.taxi_in_service[t]
                                    push!(tIDa, t)
                                    break
                                end
                            end
                        end
                    end
                end

                # also identify all vacant driving taxis with sufficient soc
                for t = 1:data.num_taxis
                    if (status.taxi_loc[t] < 0) & (status.taxi_soc[t]-SOC_MIN > soc_req) & (status.taxi_in_service[t])
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
                #push!(log.trip_taxi, 0)
                if soc_req > SOC_nominal - SOC_MIN
                    push!(log.trip_taxi, -2) # energy required exceeds taxi battery capacity 
                    push!(completed, j)
                else
                    if now(sim) >= trip.time + WAIT
                        for k in 1:data.num_taxis
                            if !((!status.taxi_in_service[k]) || (status.taxi_loc[k] == 0)) || (sum(status.rank_num_plugin) > 0) 
                                push!(log.trip_taxi, -3) # no free taxi has sufficient charge to complete trip
                                push!(completed, j)
                                break
                            elseif k == data.num_taxis
                                push!(log.trip_taxi,-1) # all taxis are completing trips
                                push!(completed, j)
                            end
                        end
                    end
                end
            else
                push!(log.trip_taxi, tID)

                # if the selected taxi will have high soc upon reaching call target, ...
                if soc_end > SOC(60)
                    trip.urgent = false

                    # ... compute route from call target to nearby rank (instead of going straight to nearest rank with charger)
                    prob = data.rank_popularity ./ (status.rank_volume .+ 1)
                    prob /= sum(prob)
                    temp_rID, temp_route3 = dijkstra_taxi_to_nearby_rank(net, target, data.rank_node, prob)
                    soc_end = status.taxi_soc[tID] - (isnothing(trip.route1) ? 0.0 : trip.route1.energy) - trip.route2.energy - sum(temp_route3.energy)

                    # drive to the nearby rank if it has chargers or soc upon reaching this rank will be > 30%
                    if !isnothing(data.rank_mode[temp_rID]) | (soc_end > 30)
                        trip.route3 = temp_route3
                        trip.rID = temp_rID
                    end
                end

                # dispatch the taxi
                status.taxi_trip[tID] = trip
                push!(completed,j)
                @yield timeout(sim, 0.0)
                #println("Dispatching taxi ", tID, " from location ", status.taxi_loc[tID])
                interrupt(taxis[tID])
                @yield timeout(sim, 0.0)
            end
        end
        deleteat!(active_trips, completed)
        if (now(sim)+1.0) == TIME
            update_charger_usage(sim, status,log)
        end
        
        update_rank_status(status)
        push!(log.rank_status_trace, deepcopy(status.rank_status))
        @yield timeout(sim, 1.0) # Waits for the next timestep to occur. 

        """
            Adding the functionality for the simulation to get completed with or without animation intervening in the process.
            Also, added the animation speed control functionality.
        """
		if ((animation_speed > 0) && (now(sim) % animation_speed == 0))
            msg = updateFrame(animation_speed, active_trips)
            animation_speed = tryparse(Float64, msg)
        end
			
    end
    # While ends here.
end

function update_queue(rID::Int64, tID::Int64, status::Status)
    # This function will move an electric taxi (tID) directly infront of the first combustion taxi
    # if one exists, otherwise the queue will remain unchanged.
    queue = status.rank_queue_electric
    taxi_pos = findfirst(isequal(tID), queue[rID])
    for i in 1:taxi_pos
        tID_check = queue[rID][i]
        if status.taxi_soc[tID_check] == Inf
            splice!(queue[rID],taxi_pos)
            splice!(queue[rID],i:(i-1),tID)
            break
        end
    end
end

function in_service(sim::Simulation,status::Status, shifts::Array{Bool})
    # Test function that controls when each taxi is in service
    time =  now(sim)
    # if time < 120
    #     for i in 1:50
    #         status.taxi_in_service[i] = true
    #         status.taxi_in_service[i+50] = true
    #     end
    # elseif time < 240
    #     for i in 1:50
    #         status.taxi_in_service[i] = true
    #         status.taxi_in_service[i+50] = true
    #     end
    # else
    #     for i in 1:50
    #         status.taxi_in_service[i] = true
    #         status.taxi_in_service[i+50] = true
    #     end
    # end
    #hour = trunc(Int64, time/60.0) + 1 + Int64(START/60.0)
    hour = (trunc(Int64, time/60.0) + Int64(START/60.0)) % 168 + 1
    for tID in 1:size(shifts,1)
        if shifts[tID,hour]
            status.taxi_in_service[tID] = true
        else
            status.taxi_in_service[tID] = !TAXI_SHIFTS
        end
    end
end

function update_charger_usage(sim::Simulation, status::Status, log::Log)
    # Final update of charger usage before simulation ends
    for i = 1:NUM_NEARBY_RANKS
        log.rank_wireless_usage[i][status.rank_num_wireless[i]+1] += now(sim) - status.rank_wireless_updated[i] + 1
        log.rank_plugin_usage[i][status.rank_num_plugin[i]+1] += now(sim) - status.rank_plugin_updated[i] + 1
    end
end

function update_charger_usage(sim::Simulation, status::Status, log::Log, rID::Int64, type::String)
    # Updates the usage of the chargers of type "type" at rank "rID"
    if type == "w"
        log.rank_wireless_usage[rID][status.rank_num_wireless[rID]+1] += now(sim) - status.rank_wireless_updated[rID] 
        status.rank_wireless_updated[rID] = now(sim)
        status.rank_num_wireless[rID] -= 1
    else
        log.rank_plugin_usage[rID][status.rank_num_plugin[rID]+1] += now(sim) - status.rank_plugin_updated[rID] 
        status.rank_plugin_updated[rID] = now(sim)
        status.rank_num_plugin[rID] -= 1
    end
end

function update_rank_status(status::Status)
    for i = 1:NUM_NEARBY_RANKS
        status.rank_status.queue[i] = status.rank_queue_electric[i]
        status.rank_status.queue_taxi_soc[i] = status.taxi_soc[status.rank_status.queue[i]]
        status.rank_status.plugin_charging_soc[i] = status.taxi_soc[status.rank_status.plugin_charging[i]]
    end
end

"""
    Finds coordinates of taxi rank in network.

    Parameters
    ----------
    net: Network
        The road network.
    data: Data 
        Contains information about each taxi rank.
    rID: Int64
        The rank ID for which the coordinates are desired.
        
    Returns
    -------
    coords: Tuple{Float64, Float64}
        The coordinates (lattitude and longitude) of the taxi rank with the ID rID.
"""
function rank_location(net::Network, data::Data, rID::Int64)
    rank_node = data.rank_node[rID]
    return node_location(rank_node, net)
end

"""
    Creates an instance of the Move_taxi struct.

    Parameters
    ----------
    sim: Simulation
        An instance of the SimJulia Simulation which controls the simulation.
    net: Network
        The road network.
    route: Route
        The route that the taxi is completing.
    tID: Int64
        The ID of the taxi which is completing the route.
    index: Union{Nothing, Int64}
        Nothing if the route cannot be disrupted, otherwise the index of the node 
        which the taxi reached before being interrupted.
    
    Returns
    --------
    move_taxi: Move_taxi
        A struct defined in types.jl that defines movement of taxi in simulation for visualisation.
"""
function generate_taxi_move(sim::Simulation, net::Network, route::Route, tID::Int64, index::Union{Nothing, Int64})  
    start_location = node_location(route.path[1], net)
    end_location = node_location(route.path[length(route.path)], net)
    if isnothing(index)
        return Move_taxi(tID, now(sim) - route.time, now(sim), start_location, end_location)
    else
        end_location = node_location(route.path[index], net) # find actual end location based on index
        if typeof(route.time) == Float64
            return Move_taxi(tID, now(sim) - route.time, now(sim), start_location, end_location)
        else
            return Move_taxi(tID, now(sim) - sum(route.time[1:index]), now(sim), start_location, end_location) 
        end
    end
end
