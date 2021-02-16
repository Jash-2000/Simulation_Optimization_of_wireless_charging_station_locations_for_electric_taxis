# retuns soc after charging for 'time' starting from 'soc'
function nonlinear_charging(model::Vector{NTuple{4,Float64}}, eff::Float64, soc::Float64, time::Float64)
    #=
        This is the main function of the simulation. It declares and initiates the main simulation environment,
        network structures and other log files to be used for visualization purposes. 
        
        Inputs -> 
        Outputs -> 

        Other user defined dependencies used :- 
            
    =#
    
    time += nonlinear_charging_time(model, soc)
    for (t, ~, m, c) in model
        if time <= t
            gain = (m * time + c) - soc
            return min(soc + gain * eff, SOC_nominal)
        end
    end
end

# Using Polymorphism to define the same function twice

# returns time it takes to charge from 0 to 'soc'
function nonlinear_charging_time(model::Vector{NTuple{4,Float64}}, soc::Float64)
    #=
        This is the main function of the simulation. It declares and initiates the main simulation environment,
        network structures and other log files to be used for visualization purposes. 
        
        Inputs -> 
        Outputs -> 

        Other user defined dependencies used :- 
            
    =#
    
    for (~, s, m, c) in model
        if soc <= s
            return (soc - c) / m
        end
    end
end

# returns time it takes to charge from 'soc1' to 'soc2'
function nonlinear_charging_time(model::Vector{NTuple{4,Float64}}, eff::Float64, soc1::Float64, soc2::Float64)
    #=
        This is the main function of the simulation. It declares and initiates the main simulation environment,
        network structures and other log files to be used for visualization purposes. 
        
        Inputs -> 
        Outputs -> 

        Other user defined dependencies used :- 
            
    =#
    
    return nonlinear_charging_time(model, soc2/eff) - nonlinear_charging_time(model, soc1/eff)
end