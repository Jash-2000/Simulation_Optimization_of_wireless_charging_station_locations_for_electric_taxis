using JLD2
using FileIO
using JuMP
using Gurobi
using DelimitedFiles
using DataFrames
using CSV

const num_ranks = 26

function simplified_MCLP_model(demand, theta, C, M)
"""
A simple MCLP model for determining the allocation of wireless chargers to ranks.

    parameters
    ----------
    demand: Array{Float64}
        Contains the wireless charging demand at each rank.
    theta: Float64
        The demand that one wireless charger can satisfy.
    C: Int64
        The total number of wireless chargers to be allocated.
    M: Array{Int64}
        The maximum number of wireless chargers at each rank.
    
    returns
    --------
    charger_locations: Array{Int64}
        The optimal number of wireless chargers to allocate to each rank.
"""
    model = Model(Gurobi.Optimizer)


    # decision variables
    @variable(model, 0<=y[1:num_ranks], Int)
    @variable(model, 0<=x[1:num_ranks]<=1)

    # objective function
    @objective(model, Max, sum(demand.*x))

    # constraints
    for rank = 1:num_ranks
        if !iszero(demand[rank])
            @constraint(model, y[rank]*theta/demand[rank] - x[rank] >= 0)
        else
            #@constraint(model, y[rank]*theta - x[rank] >= 0)
            @constraint(model, x[rank] == 1.0)
        end
        @constraint(model, y[rank] <= M[rank])
    end
    @constraint(model, sum(y) <= C)
    
    print(model)
    optimize!(model)
    termination_status(model)
    charger_locations = value.(y)
    charger_locations[charger_locations .<= 0] .= 0

    println("The optimal charger locations are ", charger_locations)
    println("The total number of chargers allocated is ", sum(value.(y)))
    println("demand fraction covered is ", value.(x))
    return charger_locations
end


jld = load("data/wireless_demand.jld2")
demand = jld["WIRELESS_DEMAND"]
theta = 168*20*0.20
C = 40
M = [20 for i in 1:num_ranks]
charger_locations = simplified_MCLP_model(demand, theta, C, M)
writedlm("optimal_charger_locations.txt", charger_locations) # writes locations to txt file.