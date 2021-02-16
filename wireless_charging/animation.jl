"""
This is the main file that uses a 3-way communication between Simulation, Javascript client and itself. 
If called, this script runs the main simulation function. 

---

Issues to be sorted 
	* Increasing/Decreasing the Animation_Speed does not increase/Decrease the simulation speed. It just starts
	communicating at a lowers/increases the sampling rate.

	* The calls remain visible until the entire duration of the trip i.e. even after the axi picks up the passensger.
"""
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
	for rank_id in 1:length(data.rank_node)
		lat, long = node_location(data.rank_node[rank_id],net)
		messageDict["rank_id"] = rank_id
		messageDict["rank_lat"] = lat
		messageDict["rank_long"] = long
		messageDict["rank_name"] = data.rank_name[rank_id]
		messageDict["rank_taxi"] = data.rank_init_taxi[rank_id]
		if data.rank_init_taxi[rank_id] > 0
			messageDict["rank_first_taxi"] = status.rank_status.queue[rank][1]
			messageDict["rank_first_soc"] = status.rank_status.queue_taxi_soc[rank][1]
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

#####################################################################################################################
#=
	Functions below perform the animation.
=# 
######################################################################################################################

"""
	Main function that communicates with the animation file i.e. Index.html.
"""
function animateClient(client::Client, data::Data, net::Network,  trips::Vector{Trip}, status::Status, log::Log, shifts::Array{Bool}, stop::Float64, sim::Simulation, animSpeed::Int64)
	
	println("Client connected")
	
	# set map
	messageDict = createMessageDict("set_map_view")
	
	southwest_lat = net.Lat[end] - 0.02
	southwest_long = net.Long[end] - 0.02

	northeast_lat = net.Lat[1] + 0.02
	northeast_long = net.Lat[1] + 0.02
	
	messageDict["map_southwest_lat"] = southwest_lat
	messageDict["map_southwest_long"] = southwest_long
	print("\n Lower Bound : ", southwest_lat, " , " ,southwest_long, "\n")
	messageDict["map_northeast_lat"] = northeast_lat
	messageDict["map_northeast_long"] = northeast_long
	print("\n Lower Bound : ", northeast_lat, " , " ,northeast_long, "\n")
	write(client, json(messageDict))
	print("\n\n Successfully sent the map setup co-ordinates\n")
	
	# Set up the simulation process.
	@process dispatcher(sim, net, trips, data, status, log, shifts, animSpeed)
	
	# Set up the start time.
	messageDict_time = createMessageDict("set_start_time")
	messageDict_time["time"] = now(sim)
	write(client, json(messageDict_time))
	
	try
		# Set up the fixed icons on the map.
		animSetIcons(client) # set icons before adding items to map
		animAddranks!(client, data, net)
		# animAddTaxis!(client, data, net, status)
	catch e
		@warn("Could not update animation icons")
		@warn(e)
	finally
		set_up_complete(client)
	end

	messageDict = createMessageDict("")
	while !eof(client)
		msg = readavailable(client) # waits for message from client?
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
					
		if msgType == "start_the_simulation"
			timmer(client, sim)
			run(sim, stop)
			writeClient!(client, messageDict, "got_last_frame")
		
		elseif msgType == "wait_for_start"
			set_up_complete(client)
		
		elseif msgType == "disconnect"
			close(client)
			println("Client disconnected")
			break
		
		else
			error("Unrecognised message: ", msgString)
		end
	
	end # While loop ends here.
	save_log(log)
end #  End of animation. The control will now go back to main.jl.

"""
	Function used for communicating with the simulation file.
"""
function updateFrame(animation_speed::Int64, active_trips::Vector{Trip})
	timmer(client, sim)

	messageDict_ranks = createMessageDict("update_ranks")
	for  rank in size(status.rank_status.queue)[1]
		messageDict["rank_taxi"] = sizeof(status.rank_status.queue[rank])[1]
		if  sizeof(status.rank_status.queue[rank])[1] > 0
			messageDict["rank_first_taxi"] = status.rank_status.queue[rank][1]
			messageDict["rank_first_soc"] = status.rank_status.queue_taxi_soc[rank][1]
		else
			messageDict["rank_first_taxi"] = 0
			messageDict["rank_first_soc"] = -100
		end
		write(client, json(messageDict_ranks))
	end

	messageDict_taxis = createMessageDict("update_taxis")
	for taxi in log.taxi_move_trace
		if ( (taxi.start_time <= now(sim)) && (now(sim) <= taxi.end_time) )
			messageDict_taxis["taxi_ID"] = taxi.tID
			(s_lat,s_long) = taxi.start_coords
			messageDict_taxis["taxi_start_coords"] = (s_lat, s_long)
			(e_lat, e_long) = taxi.end_coords
			messageDict_taxis["taxi_end_coords"] = (e_lat, e_long)
		end
		write(client, json(messageDict_taxis))
	end

	messageDict_calls = createMessageDict("update_calls")
	for t in active_trips
		lat,long = node_location(t.route2.path[1],net)
		messageDict_calls["calls_to_show_lat"] = lat
		messageDict_calls["calls_to_show_long"] = long 
		write(client, json(messageDict_calls))
	end
	
	# Reading the next instructions from the client.
	while !eof(client)
		msg = readavailable(client) # waits for message from client
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
		
		if msgType == "prepare_next_frame"			# This function shifts the control back to simulation.
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