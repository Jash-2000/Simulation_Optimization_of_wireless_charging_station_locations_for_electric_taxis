function load_network()
    jld = load(joinpath("data", "network-karlsruhe.jld"))
    return Network(jld["DISTANCE"], jld["TIME"])
end

function load_trips()
    print(joinpath("data", "trips-karlsruhe.jld"))
    jld = load(joinpath("data", "trips-karlsruhe.jld"))
    return jld["trips"]
end

function load_data(sim::Simulation)
    df = CSV.read(joinpath("data", "ranks-karlsruhe.csv"),DataFrame)
    num_ranks = size(df, 1)
    num_taxis = sum(df.TAXIS_ELECTRIC) + sum(df.TAXIS_COMBUSTION)

    data = Data(num_ranks, num_taxis)
    status = Status(num_ranks, num_taxis)
    log = Log(num_ranks, num_taxis)
    tID = 0

    for rID = 1:num_ranks
        data.rank_node[rID] = df.NODE[rID]
        data.rank_popularity[rID] = df.POPULARITY[rID]

        ne = df.TAXIS_ELECTRIC[rID]
        nc = df.TAXIS_COMBUSTION[rID]
        status.rank_volume[rID] = ne + nc

        for i = 1:ne
            tID += 1
            push!(status.rank_queue_electric[rID], tID)
            status.taxi_loc[tID] = rID
            status.taxi_soc[tID] = SOC_100
        end

        for i = 1:nc
            tID += 1
            push!(status.rank_queue_combustion[rID], tID)
            status.taxi_loc[tID] = rID
            status.taxi_soc[tID] = Inf
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

function precompute_trips(net::Network, data::Data, ind1::Int64, ind2::Int64)
    node_rank = Dict{Int64,Int64}(data.rank_node[rID] => rID for rID in 1:data.num_ranks)
    rIDc = [rID for rID in 1:data.num_ranks if !isnothing(data.rank_mode[rID])]
    rIDc_node = data.rank_node[rIDc]

    num_trips = ind2 - ind1 + 1
    trips = Vector{Trip}(undef, num_trips)

    df = CSV.read(joinpath("data", "calls-karlsruhe.csv"),DataFrame)

    for i = 1:num_trips
        ind = ind1 + i - 1
        wait = Float64(df.WAIT[ind])
        source = df.SOURCE[ind]
        target = df.TARGET[ind]

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

        trips[i] = Trip(wait, nothing, route2, route3, rID, true)
        println(i, "/", num_trips)
    end

    save(joinpath("data", "trips-karlsruhe.jld"), "trips", trips)
    println("Saved to trips-karlsruhe.jld")
end

function save_log(log::Log)
    # distance = energy / (ENERGY_PER_DISTANCE * 1000.0)
    save(joinpath("data", "log-karlsruhe.jld"), "log", log)
    println("Saved to log-karlsruhe.jld")
end
