# SCRIPT

# cd("/Users/jadexiao/Desktop/evrouting/wireless_charging")
# cd("/home/arai017/research/transport_energy/electric_vehicles/IPT_charging_project/git_bitbucket/evrouting/wireless_charging")
include("TaxiSim.jl")

# define soc thresholds for decision making; unit is kWh
const SOC_100 = 35.0
const SOC_60 = 35.0 * 0.6
const SOC_30 = 35.0 * 0.3
const SOC_END_PLUGIN = 35.0 * 0.8

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

function main(stop::Float64=Inf)
    sim = Simulation()
    net = load_network()
    trips = load_trips()
    data, status, log = load_data(sim)

    @process dispatcher(sim, net, trips, data, status, log)

    try
        @time run(sim, stop)
    finally
        save_log(log)
        return status, log
    end
end

S, L = main(6*60.0)
0

# jld = load(joinpath("data", "log-karlsruhe.jld"))
# LOG = jld["log"]

# function main(stop::Float64=Inf)
#     sim = Simulation()
#     net = load_network()
#     data, ~, ~ = load_data(sim)
#
#     @time precompute_trips(net, data, 1, 12189) # week 1
# end
#
# main()
