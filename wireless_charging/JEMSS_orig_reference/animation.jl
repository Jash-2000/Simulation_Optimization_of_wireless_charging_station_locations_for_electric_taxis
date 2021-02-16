# todo: replace instances of `Simulation` and `sim` with your own type.

const Client = HTTP.WebSockets.WebSocket{HTTP.ConnectionPool.Transaction{Sockets.TCPSocket}}
global animClients = [] # store open connections
global animSimQueue = Vector{Simulation}() # to store sims between animation request and start
global animPorts = Set{Int}() # localhost ports for animation, to be set

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

# set icons for ambulances, hospitals, etc.
function animSetIcons(client::Client)
	messageDict = createMessageDict("set_icons")
	pngFileUrl(filename) = string("data:image/png;base64,", filename |> read |> base64encode)
	iconPath = joinpath(@__DIR__, "..", "..", "assets", "animation", "icons") # todo: change path if moving 'icons' folder.
	icons = JSON.parsefile(joinpath(iconPath, "icons.json"))
	# set iconUrl for each icon
	for (name, icon) in icons
		icon["options"]["iconUrl"] = pngFileUrl(joinpath(iconPath, string(name, ".png")))
	end
	merge!(messageDict, icons)
	write(client, json(messageDict))
end

# todo: modify to be for taxis (or vehicles).
function animAddAmbs!(client::Client, sim::Simulation)
	messageDict = createMessageDict("add_ambulance")
	for amb in sim.ambulances
		copy!(amb.currentLoc, getRouteCurrentLocation!(sim.net, amb.route, sim.time)) # todo: replace with code that sets current vehicle location.
		messageDict["ambulance"] = amb
		write(client, json(messageDict))
	end
end

# todo: modify most of this function; needs to update vehicle locations for given time.
# write frame updates to client
function updateFrame!(client::Client, sim::Simulation, time::Float)
	
	# check which ambulances have moved since last frame
	# need to do this before showing call locations
	messageDict = createMessageDict("move_ambulance")
	for amb in sim.ambulances
		ambLocation = getRouteCurrentLocation!(sim.net, amb.route, time) # todo: replace with code that sets current vehicle location.
		if ambLocation != amb.currentLoc
			copy!(amb.currentLoc, ambLocation)
			amb.movedLoc = true
			# move ambulance
			messageDict["ambulance"] = amb
			write(client, json(messageDict))
		else
			amb.movedLoc = false
		end
	end
	delete!(messageDict, "ambulance")
	
end

# todo: remove or modify this function as needed.
 # update call current location
function updateCallLocation!(sim::Simulation, call::Call)
# consider moving call if the status indicates location other than call origin location
	if call.status == callGoingToHospital || call.status == callAtHospital
		amb = sim.ambulances[call.ambIndex]
		call.movedLoc = amb.movedLoc
		if amb.movedLoc
			copy!(call.currentLoc, amb.currentLoc)
		end
	end
end

function animateClient(client::Client)
	global animClients, animSimQueue
	
	push!(animClients, client)
	println("Client connected")
	
	sim = popfirst!(animSimQueue) # get first item in animSimQueue
	
	# set map
	messageDict = createMessageDict("set_map_view")
	messageDict["map"] = sim.map
	write(client, json(messageDict))
	
	# set sim start time
	messageDict = createMessageDict("set_start_time")
	messageDict["time"] = sim.startTime
	write(client, json(messageDict))
	
	animSetIcons(client) # set icons before adding items to map
	animAddAmbs!(client, sim)
	
	sim.animating = true
	
	messageDict = createMessageDict("")
	while !eof(client)
		msg = readavailable(client) # waits for message from client?
		msgString = decodeMessage(msg)
		(msgType, msgData) = parseMessage(msgString)
		
		if msgType == "prepare_next_frame"
			simTime = Float(msgData[1])
			simulateToTime!(sim, simTime) # todo: replace with your equivalent function; something like `run(env, simTime)` if using SimJulia.
			# sim.time = simTime # otherwise sim.time only stores time of last event
			messageDict["time"] = simTime
			writeClient!(client, messageDict, "prepared_next_frame")
			
		elseif msgType == "get_next_frame"
			simTime = Float(msgData[1])
			updateFrame!(client, sim, simTime) # show updated amb locations, etc
			if !sim.complete # todo: replace with your own check of whether sim has finished (no events left to simulate).
				messageDict["time"] = simTime
				writeClient!(client, messageDict, "got_next_frame")
			else
				# no events left, finish animation
				writeClient!(client, messageDict, "got_last_frame")
			end
			
		elseif msgType == "pause"
		
		# todo: uncomment and modify this code if using reset/stop feature in animation.
		# elseif msgType == "stop"
		# 	# reset
		# 	reset!(sim) # todo: replace with your own function that resets sim state back to start.
		# 	animAddAmbs!(client, sim)
			
		elseif msgType == "update_icons"
			try
				animSetIcons(client)
			catch e
				@warn("Could not update animation icons")
				@warn(e)
			end
			
		# elseif msgType == "get_arcs"
			# animAddNodes(client, sim.net.fGraph.nodes)
			# animAddArcs(client, sim.net)
			# animSetArcSpeeds(client, sim.map, sim.net)
			
		elseif msgType == "disconnect"
			sim.animating = false
			close(client)
			deleteat!(animClients, findfirst(isequal(client), animClients))
			println("Client disconnected")
			break
		else
			sim.animating = false
			error("Unrecognised message: ", msgString)
		end
	end
end

function animate!(sim::Simulation;port::Int = 8001, openWindow::Bool = true)
	#=	
	Open a web browser window to animate the simulation.
	
	# Keyword arguments
	-> `port` is the port number for the local host url, e.g. `port = 8001` will use localhost:8001
			 this can only be set once for all animation windows.
	-> `openWindow` can be set to `false` to prevent the window from being opened automatically, which is 
				useful if you wish to use a non-default browser.
	=#

	global animSimQueue
	if runAnimServer(port)
		push!(animSimQueue, sim)
		openWindow ? openLocalhost(port) : println("waiting for window with port $port to be opened")
	end
end

# creates and runs server for given port
# returns true if server is running, false otherwise
function runAnimServer(port::Int)
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
	onepage = read("$sourceDir/animation/index.html", String)
	@async HTTP.listen(Sockets.localhost, port, readtimeout = 0) do http::HTTP.Stream
		if HTTP.WebSockets.is_upgrade(http.message)
			HTTP.WebSockets.upgrade(http) do client
				animateClient(client)
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

# opens browser window for url
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

# todo: replace with your own uses of JSON.lower for objects that will be sent to javascript.
# # JSON.lower for various types, to reduce length of string returned from json function
# JSON.lower(n::Node) = Dict("index" => n.index, "location" => n.location)
# JSON.lower(a::Arc) = Dict("index" => a.index)
# JSON.lower(a::Ambulance) = Dict("index" => a.index, "currentLoc" => a.currentLoc, "endLoc" => a.route.endLoc)
# JSON.lower(c::Call) = Dict("index" => c.index, "currentLoc" => c.currentLoc, "priority" => c.priority)
# JSON.lower(h::Hospital) = Dict("index" => h.index, "location" => h.location)
# JSON.lower(s::Station) = Dict("index" => s.index, "location" => s.location)
