#=
This is the main file that uses a 3-way communication between Simulation, Javascript client and itself. 
If called, this script runs the main simulation function. 

---

Issues to be sorted 
	* Increasing/Decreasing the Animation_Speed does not increase/Decrease the simulation speed. It just starts
	communicating at a lowers/increases the sampling rate.

	* The calls remain visible until the entire duration of the trip i.e. even after the axi picks up the passensger.
=#

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
using HTTP
using Sockets
using WebSockets
using JSON
using Base64

include("TaxiSim.jl")
#########################################################################################################################################
#= 
	Developing a connection with the Frontend.
=#
##########################################################################################################################################

const Client = HTTP.WebSockets.WebSocket{HTTP.ConnectionPool.Transaction{Sockets.TCPSocket}}
# global animClients = [] # store open connections
global animPorts = Set{Int}() # localhost ports for animation, to be set


##############################################################################################
#=
	Polymorphism for dispatcher function.
=#

@resumable function Dispatcher(sim::Simulation, net::Network, trips::Vector{Trip}, data::Data, status::Status, log::Log, shifts::Array{Bool}, client::Client, animSpeed::Int64 = 0)
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
        
        println("\n Sending the first frame to animation")
        """
            Adding the functionality for the simulation to get completed with or without animation intervening in the process.
            Also, added the animation speed control functionality.
        """
		if ((animation_speed > 0) && (now(sim) % animation_speed == 0))
            msg = updateFrame(sim, log, data, status, animation_speed, active_trips, net, client)
            animation_speed = tryparse(Float64, msg)
        end
			
    end
    # While ends here.
end


"""
Open a web browser window to animate the simulation.

---

# Keyword arguments
	-> `port` is the port number for the local host url, e.g. `port = 8001` will use localhost:8001
			 this can only be set once for all animation windows.
	-> `openWindow` can be set to `false` to prevent the window from being opened automatically, which is 
				useful if you wish to use a non-default browser.
"""
function animate!(net::Network, data::Data, trips::Vector{Trip},status::Status, log::Log, shifts::Array{Bool}, stop::Float64, sim::Simulation, animSpeed::Int64, port::Int = 8001, openWindow::Bool = true)
	
	if runAnimServer(port, data, net, trips, status, log, shifts, stop, sim, animSpeed)
		openWindow ? openLocalhost(port) : println("waiting for window with port $port to be opened")
	end
end

"""
Creates and runs server for given port
Returns true if server is running, false otherwise
"""
function runAnimServer(port::Int, data::Data, net::Network, trips::Vector{Trip}, status::Status, log::Log, shifts::Array{Bool}, stop::Float64, sim::Simulation, animSpeed::Int64)
	@assert(port >= 0)
	# check if port already in use
	global animPorts
	
	if in(port, animPorts)
		return true # port already used for animation
	end
	
	try
		socket = Sockets.connect(port)
		if socket.status == Base.StatusOpen
			println("port $port is already in use, try another")
			return false
		end
	catch
	
	end
	
	# create and run server
	onepage = read("index.html", String)			# Read the HTML file which has the main code.
	@async HTTP.listen(Sockets.localhost, port, readtimeout = 0) do http::HTTP.Stream
		if HTTP.WebSockets.is_upgrade(http.message)
			HTTP.WebSockets.upgrade(http) do client
				animateClient(client, data, net, trips, status, log, shifts, stop, sim, animSpeed)
			end
		else
			h = HTTP.Handlers.RequestHandlerFunction() do req::HTTP.Request
				HTTP.Response(200, onepage)
			end
			HTTP.Handlers.handle(h, http)
		end
	end
	
	push!(animPorts, port)
	return true
end

# opens default browser window for url
function openUrl(url::String)
	if Sys.iswindows()
		run(`$(ENV["COMSPEC"]) /c start $url`)
	elseif Sys.isapple()
		run(`open $url`)
	elseif Sys.islinux() || Sys.isbsd()
		run(`xdg-open $url`)
	end
end

# opens browser window for localhost:port
function openLocalhost(port::Int)
	openUrl("http://localhost:$(port)")
end

######################################################################################################
#=
	Configuring a medium for communication with the client, through JSON files.
=#
#######################################################################################################

function decodeMessage(msg)
	return String(msg)
end

# parse message from html, extract values
function parseMessage(msg::String)
	msgSplit = readdlm(IOBuffer(msg))
	# msgType = msgSplit[1]
	# msgData = msgSplit[2:end]
	return msgSplit[1], msgSplit[2:end]
end

# create dictionary for sending messages to js
function createMessageDict(message::String)
	messageDict = Dict()
	messageDict["message"] = message
	return messageDict
end

# change message of messageDict
function changeMessageDict!(messageDict::Dict, message::String)
	messageDict["message"] = message
end

function writeClient!(client::Client, messageDict::Dict, message::String)
	# common enough lines to warrant the use of a function, I guess
	changeMessageDict!(messageDict, message)
	write(client, json(messageDict))
end

##############################################################################################################
#=
	Helper Functions.
=#
###############################################################################################################

function animSetIcons(client::Client)
	messageDict = createMessageDict("set_icons")
	pngFileUrl(filename) = string("data:image/png;base64,", filename |> read |> base64encode)
	iconPath = joinpath(@__DIR__, "assets", "animation", "icons")
	icons = JSON.parsefile(joinpath(iconPath, "icons.json"))
	# set iconUrl for each icon
	for (name, icon) in icons
		icon["options"]["iconUrl"] = pngFileUrl(joinpath(iconPath, string(name, ".png")))
	end
	merge!(messageDict, icons)
	write(client, json(messageDict))
end

function animAddranks!(client::Client, data::Data, net::Network)
	messageDict = createMessageDict("add_ranks")
	taxi_no = 1
	for rank_id in 1:length(data.rank_node)
		lat, long = node_location(data.rank_node[rank_id],net)
		messageDict["rank_id"] = rank_id
		messageDict["rank_lat"] = lat
		messageDict["rank_long"] = long
		messageDict["rank_name"] = data.rank_name[rank_id]
		messageDict["rank_taxi"] = data.rank_init_taxi[rank_id]
		if data.rank_init_taxi[rank_id] > 0
			messageDict["rank_first_taxi"] = taxi_no
			messageDict["rank_first_soc"] = 100
			taxi_no = taxi_no + data.rank_init_taxi[rank_id]
		else
			messageDict["rank_first_taxi"] = 0
			messageDict["rank_first_soc"] = -100
		end
		print("\n Done sending rank : ", data.rank_name[rank_id])
		write(client, json(messageDict))
	end
end

function animAddTaxis!(client::Client, data::Data, net::Network, status::Status)
	messageDict = createMessageDict("add_taxis_to_ranks")
	tID = 1
	for rankID in status.taxi_loc
		messageDict["taxi_id"] = tID
		lat,long = node_location(data.rank_node[tID],net)
		messageDict["taxi_lat"] = lat
		messageDict["taxi_long"] = long

		print("\n Done sending taxi with ID : ", tID)
		tID = tID + 1

		write(client, json(messageDict))
	end
end	


function timmer(client::Client, sim::Simulation)
	messageDict = createMessageDict("Current_time")
	messageDict["time"] = now(sim)
	write(client, json(messageDict))
end

function set_up_complete(client::Client)
	messageDict = createMessageDict("set_up_complete")
	write(client, json(messageDict))
end

#####################################################################################################################
#=
	Functions below perform the animation.
=# 
######################################################################################################################

"""
	Function used for communicating with the simulation file.
"""
function updateFrame(sim::Simulation, log::Log, data::Data, status::Status, animation_speed::Int64, active_trips::Vector{Trip}, net::Network, client::Client)
	println("\nGot a frame")
	timmer(client, sim)
	
	messageDict_ranks = createMessageDict("update_ranks")
	for  rank in size(status.rank_status.queue)[1]
		lat, long = node_location(data.rank_node[rank],net)
		messageDict_ranks["rank_id"] = rank
		messageDict_ranks["rank_lat"] = lat
		messageDict_ranks["rank_long"] = long
		messageDict_ranks["rank_name"] = data.rank_name[rank]
		messageDict_ranks["rank_taxi"] = sizeof(status.rank_status.queue[rank])[1]
		if  sizeof(status.rank_status.queue[rank])[1] > 0
			messageDict_ranks["rank_first_taxi"] = status.rank_status.queue[rank][1]
			messageDict_ranks["rank_first_soc"] = status.rank_status.queue_taxi_soc[rank][1]
		else
			messageDict_ranks["rank_first_taxi"] = 0
			messageDict_ranks["rank_first_soc"] = -100
		end
		write(client, json(messageDict_ranks))
	end
	
	msg = readavailable(client) # waits for message from client
	msgString = decodeMessage(msg)
	(msgType, msgData) = parseMessage(msgString)
	while (msgType != "Ranks_updated")
		msg = readavailable(client) # waits for message from client
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
	end
	println("\nUpdated the ranks for time ", now(sim))
	
	messageDict_taxis = createMessageDict("update_taxis")
	for taxi in log.taxi_move_trace
		if ( (taxi.start_time <= now(sim)) && (now(sim) <= taxi.end_time) )
			messageDict_taxis["taxi_ID"] = taxi.tID
			(s_lat,s_long) = taxi.start_coords
			messageDict_taxis["taxi_start_lat"] = s_lat
			messageDict_taxis["taxi_start_long"] = s_long
			(e_lat, e_long) = taxi.end_coords
			messageDict_taxis["taxi_end_lat"] = e_lat
			messageDict_taxis["taxi_end_long"] = e_long
		end
		write(client, json(messageDict_taxis))
	end
	msg = readavailable(client) # waits for message from client
	msgString = decodeMessage(msg)
	(msgType, msgData) = parseMessage(msgString)
	while (msgType != "Taxis_updated")
		msg = readavailable(client) # waits for message from client
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
	end
	
	println("\nUpdated the taxi for time", now(sim))

	messageDict_calls = createMessageDict("update_calls")
		i = 0
		for t in active_trips
			i = i+1
			messageDict_calls["active_id"] = i
			lat,long = node_location(t.route2.path[1],net)
			messageDict_calls["calls_to_show_lat"] = lat
			messageDict_calls["calls_to_show_long"] = long 
			write(client, json(messageDict_calls))
		end
		i = 0

		msg = readavailable(client) # waits for message from client
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
		while (msgType != "Calls_updated")
			msg = readavailable(client) # waits for message from client
			msgString = decodeMessage(msg)
			(msgType, msgData) = parseMessage(msgString)
		end
		println("\nUpdated the calls for time ", now(sim))
		
		
		sleep(2)			# Pause the exectution for 2 seconds for the user to interact with the animation.
		messageDict = createMessageDict("ready_for_next_frame")
		
		# Reading the next instructions from the client.
	while true
		
		msg = readavailable(client) # waits for message from client
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
		
		if msgType == "prepare_next_frame"			# This function shifts the control back to simulation.
			println("Prepaing the next frame")
			break

		elseif msgType == "Animation_Speed"
			animation_speed = msgData[1]

		elseif msgType == "pause"
			continue

		elseif msgType == "stop"
			animation_speed = 0						# To bypass the animation loop in TaxiSim
			close(client)
			break
		
		else
			error("Unrecognised message: ", msgString)
		end

	end

	return animation_speed
end

"""
	Main function that communicates with the animation file i.e. Index.html.
"""
function animateClient(client::Client, data::Data, net::Network,  trips::Vector{Trip}, status::Status, log::Log, shifts::Array{Bool}, stop::Float64, sim::Simulation, animSpeed::Int64)
	
	println("Client connected")
	
	# set map
	messageDict = createMessageDict("set_map_view")
	
	southwest_lat = net.Lat[end] - 0.02
	southwest_long = net.Long[end] - 0.02

	northeast_lat = 49.80963
	northeast_long = 
	
	messageDict["map_southwest_lat"] = southwest_lat
	messageDict["map_southwest_long"] = southwest_long
	print("\n Lower Bound : ", southwest_lat, " , " ,southwest_long, "\n")
	messageDict["map_northeast_lat"] = northeast_lat
	messageDict["map_northeast_long"] = northeast_long
	print("\n Lower Bound : ", northeast_lat, " , " ,northeast_long, "\n")
	write(client, json(messageDict))
	print("\n\nSuccessfully sent the map setup co-ordinates\n")
	
	# Set up the simulation process.
	@process Dispatcher(sim, net, trips, data, status, log, shifts,client, animSpeed)
	
	# Set up the start time.
	messageDict_time = createMessageDict("set_start_time")
	messageDict_time["time"] = now(sim)
	write(client, json(messageDict_time))
	
	try
		# Set up the fixed icons on the map.
		animSetIcons(client) # set icons before adding items to map
		println("Set icons")
		animAddranks!(client, data, net)
		println("\nDone adding all the ranks\n")
		# animAddTaxis!(client, data, net, status)
	catch e
		@warn("Could not update animation icons")
		@warn(e)
	end

	messageDict = createMessageDict("")
	while true
		set_up_complete(client)

		msg = readavailable(client) 
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
					
		if msgType == "start_the_simulation"
			break
		elseif msgType == "wait_for_start"
			continue
		elseif msgType == "prepare_next_frame"
			break
		elseif msgType == "pause"
			continue
		else
			error("Unrecognised message: ", msgString)
		end
	end
	
	println("\nThe animation has succesfully started a communication link with the simulation")
	timmer(client, sim)
	run(sim, stop)
	println("\n The simulation is completed now. Stopping the process now!!! ")
	writeClient!(client, messageDict, "got_last_frame")
	
	msg = readavailable(client) 
	msgString = decodeMessage(msg)
	(msgType, msgData) = parseMessage(msgString)

	if msgType == "disconnect"
		close(client)
		println("Client disconnected")
	else
		error("Can not close the connection", msgString)
	end		

	save_log(log)
end #  End of animation. The control will now go back to main.jl.

