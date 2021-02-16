using CSV
using DelimitedFiles
using JLD
using SparseArrays

const ratio = pi/180    # multiplier for degree-to-radians conversion
const radius = 6371000	# radius of the earth in metres [1]

function within_bounds(t::Int64)
   slat = SLAT[t]
   slon = SLON[t]
   tlat = TLAT[t]
   tlon = TLON[t]
   return (slat > minlat) && (slat < maxlat) && (slon > minlon) && (slon < maxlon) && (tlat > minlat) && (tlat < maxlat) && (tlon > minlon) && (tlon < maxlon)
end

# =================================================================
# LOAD DATA

cd("/Users/jadexiao/Desktop/evrouting/wireless_charging")

jldopen("data/network-karlsruhe.jld") do fn
   global LAT = read(fn, "LATITUDE")
   global LON = read(fn, "LONGITUDE")
   global num_nodes = length(LAT)
   for v = 1:num_nodes
      LAT[v] *= ratio
      LON[v] *= ratio
   end
   global minlat = minimum(LAT)
   global minlon = minimum(LON)
   global maxlat = maximum(LAT)
   global maxlon = maximum(LON)
end

open("data/ranks-karlsruhe.csv") do fn
   data = CSV.read(fn)
   global num_ranks = size(data,1)
   global RNODE = zeros(Int64, num_ranks)
   for r = 1:num_ranks
       RNODE[r] = data.NODE[r]
   end
end

open("data/TripsKA_SharedWithUoA.csv") do fn
   data = CSV.read(fn)
   global num_trips = size(data,1)
   global SLAT = zeros(Float64, num_trips)
   global SLON = zeros(Float64, num_trips)
   global TLAT = zeros(Float64, num_trips)
   global TLON = zeros(Float64, num_trips)
   global DAY = zeros(Int64, num_trips)
   global HOUR = zeros(Int64, num_trips)
   global MIN = zeros(Int64, num_trips)
   for t = 1:num_trips
      SLAT[t] = ratio * data[3][t]
      SLON[t] = ratio * data[2][t]
      TLAT[t] = ratio * data[5][t]
      TLON[t] = ratio * data[4][t]
      DAY[t] = data[9][t]
      HOUR[t] = data[10][t]
      MIN[t] = data[11][t]
   end
end

# =================================================================
# GET TRIPS WITHIN BOUNDS

useful = [t for t in 1:num_trips if within_bounds(t)]
num_trips = length(useful)
SLAT = SLAT[useful]
SLON = SLON[useful]
TLAT = TLAT[useful]
TLON = TLON[useful]

# =================================================================
# MAP SOURCE AND TARGET COORDINATES TO NODES

useful2 = Vector{Int64}()
source_node = Vector{Int64}()
target_node = Vector{Int64}()
source_at_rank = zeros(Int64, num_ranks)

for t = 1:num_trips
   print("trip $t/$num_trips: ")
   snode = 0
   sdist = Inf
   tnode = 0
   tdist = Inf
   slat = SLAT[t]
   slon = SLON[t]
   tlat = TLAT[t]
   tlon = TLON[t]

   for v = 1:num_nodes
     vlat = LAT[v]
     vlon = LON[v]
     d = radius * acos(sin(slat) * sin(vlat) + cos(slat) * cos(vlat) * cos(slon - vlon))
     if d < sdist
         snode = v
         sdist = d
     end
     d = radius * acos(sin(tlat) * sin(vlat) + cos(tlat) * cos(vlat) * cos(tlon - vlon))
     if d < tdist
         tnode = v
         tdist = d
     end
   end

   print("source to node $snode, target to node $tnode")

   slat = LAT[snode]
   slon = LON[snode]

   rid = 0
   for r = 1:num_ranks
      rnode = RNODE[r]
      if rnode == snode
         continue
      end
      rlat = LAT[rnode]
      rlon = LON[rnode]
      d = radius * acos(sin(slat) * sin(rlat) + cos(slat) * cos(rlat) * cos(slon - rlon))
      if d < 100
         rid = r
         snode = rnode
         print(", source to rank $r")
         break
      end
   end

   print("\n")

   if snode != tnode
      push!(useful2, t)
      push!(source_node, snode)
      push!(target_node, tnode)
      source_at_rank[rid] += 1
   end
end

num_trips = length(useful2)
DAY = DAY[useful2]
HOUR = HOUR[useful2]
MIN = MIN[useful2]

writedlm("data/useful2.txt", useful2)
writedlm("data/source_node.txt", source_node)
writedlm("data/target_node.txt", target_node)
writedlm("data/day.txt", DAY)
writedlm("data/hour.txt", HOUR)
writedlm("data/min.txt", MIN)
writedlm("data/source_at_rank.txt", source_at_rank)

# =================================================================
# GROUP TRIPS BY DAY_HOUR

DAY_HOUR = Dict{String, Vector{Tuple{Int64, Int64, Int64, Int64}}}()

for d = 1:7
   for h = 0:23
      DAY_HOUR[string(d)*"_"*string(h)] = Vector{Tuple{Int64, Int64, Int64, Int64}}()
   end
end

for t = 1:num_trips
   push!(DAY_HOUR[string(DAY[t])*"_"*string(HOUR[t])], (MIN[t], useful2[t], source_node[t], target_node[t]))
end

num_day_hour = zeros(Int64, length(DAY_HOUR))

i = 0
for d = 1:7
   for h = 0:23
      global i += 1
      num_day_hour[i] = length(DAY_HOUR[string(d)*"_"*string(h)])
   end
end

save("data/DAY_HOUR.jld", "DAY_HOUR", DAY_HOUR)
writedlm("data/num_day_hour.txt", num_day_hour)

# =================================================================
# DIVIDE TRIPS IN EACH DAY_HOUR INTO WEEK_DAY_HOUR AND SORT

WEEK_DAY_HOUR = Dict{String, Vector{Tuple{Int64, Int64, Int64, Int64}}}()

for w = 1:4
   for d = 1:7
      for h = 0:23
         WEEK_DAY_HOUR[string(w)*"_" *string(d)*"_"*string(h)] = Vector{Tuple{Int64, Int64, Int64, Int64}}()
      end
   end
end

for d = 1:7
   for h = 0:23
      trips = DAY_HOUR[string(d)*"_"*string(h)]
      w = 1
      for t = 1:length(trips)
         push!(WEEK_DAY_HOUR[string(w)*"_" *string(d)*"_"*string(h)], trips[t])
         w += 1
         if w == 5
            w = 1
         end
      end
   end
end

num_week_day_hour = zeros(Int64, length(WEEK_DAY_HOUR))

i = 0
for w = 1:4
   for d = 1:7
      for h = 0:23
         global i += 1
         key = string(w)*"_"*string(d)*"_"*string(h)
         num_week_day_hour[i] = length(WEEK_DAY_HOUR[key])
         sort!(WEEK_DAY_HOUR[key])
      end
   end
end

save("data/WEEK_DAY_HOUR.jld", "WEEK_DAY_HOUR", WEEK_DAY_HOUR)
writedlm("data/num_week_day_hour.txt", num_week_day_hour)

# =================================================================
# COMBINE ORDERED TRIPS AND CONVERT INTO SIMULATION TIME

FINAL = zeros(Int64, num_trips, 8)

t = 0
for w = 1:4
   for d = 1:7
      for h = 0:23
         trips = WEEK_DAY_HOUR[string(w)*"_"*string(d)*"_"*string(h)]
         for i = 1:length(trips)
            global t += 1
            trip = trips[i]
            FINAL[t,1] = trip[2]
            FINAL[t,2] = w
            FINAL[t,3] = d
            FINAL[t,4] = h
            FINAL[t,5] = trip[1]
            FINAL[t,7] = trip[3]
            FINAL[t,8] = trip[4]
         end
      end
   end
end

for t = 2:num_trips
   if FINAL[t-1,4] == FINAL[t,4]
      FINAL[t,6] = FINAL[t,5] - FINAL[t-1,5]
   else
      FINAL[t,6] = 60 - FINAL[t-1,5] + FINAL[t,5]
   end
end

writedlm("data/FINAL.csv", FINAL, ",")

# =================================================================
# REFERENCES

# [1] Rolf Nungesser's Master Thesis
