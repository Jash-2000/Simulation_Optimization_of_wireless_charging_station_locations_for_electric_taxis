# This file contains all the simulation parameters

# In this scripts, everywhere the charge remaining in the battery is actually referenced by "SOC_" variable, with units Ampere-hour.
# The variable x below, actually denotes SOC in %

function SOC(x)
	return SOC_nominal * x / 100
end

# define soc thresholds for decision making.
const SOC_nominal = 35.0						

const SOC_END_PLUGIN = SOC(80)
const SOC_MIN = SOC(0)

# models are specified as piecewise linear functions, specified by the tuple (t,s,m,c)
# (t,s) = (time,soc) coordinate of the ending point of the piece; m = gradient; c = intercept
# all models start at (0,0) and end at (Inf,Inf)
# gradient m has units [kWh / minute] = [kWh per hour] / [60 minutes]
const MODEL_PLUGIN = [(33.6, 28.0, 50.0/60.0, 0.0), (Inf, Inf, 25.0/60.0, 14.0)]
const MODEL_WIRELESS = [(Inf, Inf, 20.0/60.0, 0.0)]

# e.g., real_soc = initial_soc + charge_gain * EFFICIENCY_WIRELESS
# plugin charging is assumed to have 100% efficiency
const EFFICIENCY_WIRELESS = 0.9

# energy consumption (kWh) per distance travelled (metres), assumed 25 kWh / 100 km
const ENERGY_PER_DISTANCE = 0.00025

# consider the closest [NUM_NEARBY_RANKS] ranks when deciding a rank to travel to after drop-off
const NUM_NEARBY_RANKS = 26

# time to run simulation. User needs to input the value for TIME and START. Defined in minutes.
const START = 0*60.0 # must be multiple of 60.0                   
const TIME = 6*60.0 # length of time to run simulation (In this case it is 6 hrs)               

# boolean that controls whether combustion and electric taxis share the same queue
# NOTE: combustion taxis will never cover wireless charging spots in queue
const ONE_QUEUE = false

# boolean that determines if electric taxis take priority over combustion taxis when they share the same queue
const ELECTRIC_FIRST = false

# boolean that determines if taxis operate shifts instead of constantly
const TAXI_SHIFTS = true

# Time passengers are willing to wait for taxi to be dispatched
const WAIT = 0.0

# Default Speed of the animation, at start of the visualisation. The user can change this afterwards.
const animSpeed = 1