# This script contains code to determine the taxi shifts for the simulation
using CSV
using JLD2
using DataFrames
using Statistics
using FileIO
using Gadfly
using JuMP
using Gurobi


const NUM_TAXIS = 100
const T = 7*24

"""
Produces a histogram of the route times from a simulation run.

Notes
-----
-Need to run main.jl first to load required packages
-The vertical orange line shows the mean route time and the vertical red line shows the median route time.
"""
function plot_route_times()
    jld = load("data/log-karlsruhe.jld2")
    sim_log = jld["log"]

    total_route_times = Vector{Float64}()
    for tID in 1:100
        for trip in 1:length(sim_log.taxi_route1_time[tID]) 
            try
                push!(total_route_times, (sim_log.taxi_route1_time[tID][trip] + sim_log.taxi_route2_time[tID][trip] + sim_log.taxi_route3_time[tID][trip]))
            catch
                println("Failed to add trip, tID: ", tID ) # occurs when taxi was compleing trip when simulation ended
            end
        end
    end
    mean_route_time = mean(total_route_times)
    println(mean_route_time)
    median_route_time = median(total_route_times)
    println(median_route_time)
    p = plot(x=total_route_times,xintercept=[mean_route_time,median_route_time], Geom.vline(color=["orange","red"]),
            Geom.histogram(bincount=100,density=true, limits=(min=0,)), Guide.title("Histogram of Taxi Trip Times"), 
            Guide.xlabel("Trip Time (minutes)"))
    img = SVG("data/plots/route_time_plot.svg", 6inch, 4inch)
    draw(img,p)
end

"""
Finds the average expected number of calls for each one hour time period.
"""
function expected_num_calls()
    df = CSV.File(joinpath("data", "calls-karlsruhe.csv")) |> DataFrame
    n_t = zeros(Int64, 1,672)
    num_trips = size(df,1)
    for i in 1:num_trips
        t = 168*(df.WEEK[i]-1) + 24*(df.DAY[i]-1) + df.HOUR[i]
        n_t[t+1] += 1
    end
    times = [i for i in 1:672]  
    save("data/taxi_demand.jld2", "DEMAND", n_t)
    #p = plot(x=times, y = n_t, Geom.line(), Guide.title("Taxi trips per hour over 4 weeks"), Guide.xlabel("Time Period"), Guide.ylabel("Number of trips"))
    p = plot(x=times[1:168], y = n_t[1:168], Geom.line(), Guide.title("Taxi Trips Per Hour Over Week One"), Guide.xlabel("Time From Saturday Midnight (hours)"), Guide.ylabel("Number of Trips"))
    img = SVG("data/plots/taxi_demand_plot.svg", 6inch, 4inch)
    draw(img,p)
end

""" 
Creates a taxi shift schedule from the optimal solution found from taxi shift LP.

Parameters
----------
taxi_shifts: Array{Float64,2}
    A T x n array where T is the number of discrete time periods and n is the number of different shift lengths. 
shift_lengths: Array(Float64,1)
    A n length array where n is the number of different shift lengths. Each element of the array is a length of a 
    shift that the taxis can operate

Outputs
-------
taxi_shift_schdule.csv: CSV file
    Contains a t x T array where t is the number of taxis and T is the number of discrete time periods, 
    element[t,T] is true if taxi t is operating during time period T otherwise false. Saved in data folder.
"""
function shift_schedule(taxi_shifts, shift_lengths)
    operating = Array{Bool, 2}(undef,NUM_TAXIS,T)
    operating .= false
    taxi_index = 1
    for t in 1:T
        for sl in 1:length(shift_lengths)
            for i in 1:taxi_shifts[t,sl]
                if (t+shift_lengths[sl]) <= T
                    operating[taxi_index, t:t+shift_lengths[sl]-1] .= true
                else
                    operating[taxi_index, t:T] .= 1
                    operating[taxi_index, 1:(t+shift_lengths[sl]-1-T)] .= true
                end
                if taxi_index < NUM_TAXIS
                    taxi_index += 1
                else
                    taxi_index = 1
                end
            end
        end
    end
    df = DataFrame(operating)
    CSV.write("data/taxi_shift_schedule.csv", df)
end

"""
Simplified model for taxi shifts for one day where there is only shifts of one time length.

Inputs
------
c: Int64
    The number of trips a taxi can complete in one hour.
n: Array{Int64}
    The number of taxi calls for each one hour time period over one day.

Notes
-----
-Need to run from workspace that has not run main.jl.
-Wrapping means shifts that start at the end of the week and continue into the 
start of the following week e.g. a  4 shift starting at 10pm on Saturday will 
finish at 2am on Sunday with wrapping but without wrapping shift would finish
at 12am on Sunday.
"""
function one_shift_length_model(c::Float64, n::Array{Int64})

    model = Model(Gurobi.Optimizer)
    #n = [192, 213, 245, 226, 192, 160, 72, 46, 38, 40, 48, 44, 43, 38, 68, 42, 58, 58, 55, 56, 54, 66, 62, 71]

    # Decision variables
    @variable(model,0<=x[1:24]<=NUM_TAXIS,Int)

    # Objective Function
    @objective(model, Min, 4*sum(x))

    # Constraints
    for i in 1:24
        if i > 3
            @constraint(model, c*(sum(x[(i-3):i])) >= n[i])
            @constraint(model, sum(x[(i-3):i]) <= NUM_TAXIS)
        else
            @constraint(model, c*(sum(x[1:i])+ sum(x[(24-(3-i)):24])) >= n[i]) 
            @constraint(model, sum(x[1:i]) + sum(x[(24-(3-i)):24])  <= NUM_TAXIS) 
        end
    end

    print(model)
    optimize!(model)
    termination_status(model)
    optimal_solution = value.(x)
    optimal_solution[optimal_solution .<= 0] .= 0.0
    println("The total number of taxi hours ", 4*sum(optimal_solution))
    println("The number of taxis operating in each shift ", optimal_solution)

end

"""
Model for taxi shifts over one week with shifts of length 4,6,8 hours.

Inputs
------
c: Int64
    The number of trips a taxi can complete per hour.
demand: Array{Int64}
    The number of taxi calls for each one hour time period over one week.

Outputs
--------
see shift_schedule function. 

Notes
-----
-Need to run from workspace that has not run main.jl.
-Wrapping means shifts that start at the end of the week and continue into the 
start of the following week e.g. a  4 shift starting at 10pm on Saturday will 
finish at 2am on Sunday with wrapping but without wrapping shift would finish
at 12am on Sunday.
"""
function full_shift_model(c::Float64, demand::Array{Int64})

    model2 = Model(Gurobi.Optimizer)
    n = demand[1:T]
    sl = [4,6,8] # Shift lengths

    # Decision variables
    @variable(model2, 0<=x[1:T, 1:3] <= NUM_TAXIS, Int)

    # Objective Function
    weight = 2  # HOW DO YOU DETERMINE APPROPRIATE WEIGHT?
    @objective(model2, Min, sl[1]*sum(x[:,1])+ sl[2]*sum(x[:,2]) + sl[3]*sum(x[:,3]) + weight*(sum(x[:,1]) + sum(x[:,2]) + sum(x[:,3]))) 

    # Adding constraints for each time period
    for i in 1:T
        # Active shifts in period i without any wrapping
        if i > (sl[3]-1)
            s1 = [j for j in (i-(sl[1]-1)):i]
            s2 = [j for j in (i-(sl[2]-1)):i]
            s3 = [j for j in (i-(sl[3]-1)):i]

        # Active shifts in period i with longest shift wrapping
        elseif (sl[2]-1) < i <= (sl[3]-1)
            s1 = [j for j in (i-(sl[1]-1)):i]
            s2 = [j for j in (i-(sl[2]-1)):i]
            s3 = cat([j for j in 1:i], [k for k in (T-(sl[3]-1)+i):T], dims=1)

        # Active shifts in period i with two longest shifts wrapping
        elseif (sl[1]-1) < i <= (sl[2]-1)
            s1 = [j for j in (i-(sl[1]-1)):i]
            s2 = cat([j for j in 1:i], [k for k in (T-(sl[2]-1)+i):T], dims=1)
            s3 = cat([j for j in 1:i], [k for k in (T-(sl[3]-1)+i):T], dims=1)

        # Active shifts in period i with all shifts wrapping
        else
            s1 = cat([j for j in 1:i],[k for k in (T-(sl[1]-1)+i):T], dims=1)
            s2 = cat([j for j in 1:i], [k for k in (T-(sl[2]-1)+i):T], dims=1)
            s3 = cat([j for j in 1:i], [k for k in (T-(sl[3]-1)+i):T], dims=1)
        end

        # The number of operating taxis must be able to meet demand
        @constraint(model2, c*(sum(x[s1,1]) + sum(x[s2,2]) + sum(x[s3,3])) >= n[i])

        # The number of operating taxis must not exceed the total number of taxis
        @constraint(model2, sum(x[s1,1]) + sum(x[s2,2]) + sum(x[s3,3]) <= NUM_TAXIS)
    end

    #print(model2)
    optimize!(model2)
    termination_status(model2)
    
    # RESULTS
    optimal_solution2 = value.(x[:,:])
    optimal_solution2[optimal_solution2 .<= 0] .= 0.0
    global total_taxi_hours = 0    
    for i in 1:T
        for j in 1:length(sl)
            global total_taxi_hours += sl[j]*value(x[i,j])
        end
    end
    println("The total number of taxi hours is ", total_taxi_hours)
    println("The total number of 4 hour shifts is ", sum(optimal_solution2[:,1]))
    println("The total number of 4 hour shifts is ", sum(optimal_solution2[:,2]))
    println("The total number of 4 hour shifts is ", sum(optimal_solution2[:,3]))

    # df = DataFrame(optimal_solution2)
    # CSV.write("LP_SOLUTION.csv", df) # writes solution to csv file
    # Generate taxi shifts
    shift_schedule(optimal_solution2, sl)
    # println("The 4 hour shifts ", optimal_solution2[:,1])
    # println("The 6 hour shifts ", optimal_solution2[:,2])
    # println("The 8 hour shifts ", optimal_solution2[:,3])
    
end

# Simplified full model constraints where shifts to not wrap between weeks
# e.g. 4 hour shift starting on Saturday at 10pm will finish at 12am instead 
# of wrapping till 2am on Sunday of the next week

# for i in 1:T
#     if i > (sl[3]-1)
#         s1 = [j for j in (i-(sl[1]-1)):i]
#         s2 = [j for j in (i-(sl[2]-1)):i]
#         s3 = [j for j in (i-(sl[3]-1)):i]

#     elseif (sl[2]-1) < i <= (sl[3]-1)
#         s1 = [j for j in (i-(sl[1]-1)):i]
#         s2 = [j for j in (i-(sl[2]-1)):i]
#         s3 = [j for j in 1:i]

#     elseif (sl[1]-1) < i <= (sl[2]-1)
#         s1 = [j for j in (i-(sl[1]-1)):i]
#         s2 = [j for j in 1:i]
#         s3 = s2

#     else
#         s1 = [j for j in 1:i]
#         s2 = s1
#         s3 = s1
#     end
#     @constraint(model2, c*(sum(x[s1,1]) + sum(x[s2,2]) + sum(x[s3,3])) >= n[i])
#     @constraint(model2, sum(x[s1,1]) + sum(x[s2,2]) + sum(x[s3,3]) <= NUM_TAXIS)
# end


# Find shifts for taxis when each taxi can complete 4 trips per hour.
c = 4
jld = load(joinpath("data", "taxi_demand.jld2"))
demand = jld["DEMAND"]
full_shift_model(c,demand)