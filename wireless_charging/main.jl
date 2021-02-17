# PATH SCRIPT

# cd("/Users/jadexiao/Desktop/evrouting/wireless_charging")
# cd("/home/arai017/research/transport_energy/electric_vehicles/IPT_charging_project/git_bitbucket/evrouting/wireless_charging")
# cd/Users/antonaish/documents/SRS/evrouting
# cd("/Users/Jash Shah/Desktop/NZ_Project/evrouting_main/evrouting/wireless_charging")

include("parameters.jl")
include("animation.jl")
include("TaxiSim.jl")

print("Process has successfully started now!!!!!! \n")
print("Do you wish to see the animation as well ?? : ")
#ans = readline()
ans = "Y"                     # Just while testing animation script.

"""
      This is the main function of the simulation. It declares and initiates the main simulation environment,
      network structures and other log files to be used for visualization purposes. 
      
      The animation will open up in the default browser.
        
      Inputs -> stop time {Float64} 
      Outputs -> log data {struct} and status data {struct}

      Other user defined dependencies used :- 
          -> load_network(), load_trips(), load_data() and save_log() present in data.jl
          -> dispatcher function present in TaxiSim.jl
"""
function main(stop::Float64=Inf, ans::String="NO" )
   println("\nLoading the network, please wait\n")
   sim = Simulation()                  # Defining the simulation environment for DES.
   
   net = load_network()
   trips = load_trips()
   shifts = load_shifts()
   data, status, log = load_data(sim)

   if (uppercase(ans) == "NO" || uppercase(ans) == "N" )
         
      in_service(sim,status, shifts)
      @process dispatcher(sim, net, trips, data, status, log, shifts)
      
      # try-catch-finally takes 10% more time in execution.
      #= 
      if (sim == true)
          # Run the simulation till "stop" time has been reached.
         @time run(sim, stop)            # @time macro is used to calculate and print the execution time.
         print(" \n\n Now saving the log files ")
         save_log(log)    
    
      else
         print("\n There is some kind of error \n")
    
      end
      =# 
      try
         # Run the simulation till "stop" time has been reached.
         @time run(sim, stop)  # @time macro is used to calculate and print the execution time.
         println("Completed")
      catch e
         print("There is some error")
      finally
         print(" \n\n Now saving the log files ")
         save_log(log)
         return status, log
      end
   
   elseif (uppercase(ans) == "YES" || uppercase(ans) == "Y" )
      @time animate!(net, data, trips, status, log, shifts, stop, sim, animSpeed)
      return status, log  
   
   else
      println("\n Please enter a correct alternative........... Process terminating !!!")
      return status, log
   end

end

S, L = main(TIME, ans)
print("\n In the next line, type ' print(S) ' to see the final values of Status and type ' print(L)' to see the final values of Log")