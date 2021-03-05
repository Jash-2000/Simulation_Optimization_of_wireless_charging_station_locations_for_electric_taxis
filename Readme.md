# Wireless Charger Simulation

This project was part of my winter research internship at the **[University of Auckland](https://www.auckland.ac.nz/en.html)** from November 2020 to March 2021, under supervision of **[Dr. Andrea Raith](https://unidirectory.auckland.ac.nz/profile/a-raith)**, Senior Lecturer in the Department of Engineering Science. 

Exact details about the project and the script files are **confidential** and hence, this repository contains just the literature review files and the final result of the animation. This extended Readme also contains the main Readme file of the project. [Animation_Readme](https://github.com/Jash-2000/Simulation_Optimization_of_wireless_charging_station_locations_for_electric_taxis/blob/main/Animation_Readme.md) also contains visual aid for the steps to run the project.


### **Tech Stack** 
   * [Mapbox-GL-js](https://www.mapbox.com/) APIs for implementing GIS( Geographic Information System ).
   * Javascript-JQuery (and HTML-CSS) for Front-end connection with the Julia Server.
   * [SimJulia](https://simjuliajl.readthedocs.io/en/stable/welcome.html) for implementing DES( Discrete Event Simulation ) in Julia.
   * [Gurobi](https://www.gurobi.com/) optimizer for solving Heuristic and Linear Programming paradigms.
   * Python wrapper of [OSM( Open Street Maps )](https://wiki.openstreetmap.org/wiki/Osmapi) for building the network and getting Geo-Spatial information.
   * Julia based Client with dynamic web-socket, enabling JSON based communication.


## [Aim of the project](https://www.auckland.ac.nz/en/study/scholarships-and-awards/scholarship-types/undergraduate-scholarships/summer-research-scholarships/summer-research-projects/engineering/engineering-science.html)

Electric passenger cars together with clean electricity generation lead to decreasing environmental impacts on urban societies. While battery prices are still high, it is most profitable to first electrify those cars that provide a high annual inner-city mileage. Each replacement of a conventional car leads to high emission reductions and – due to lower variable costs of electrical compared to conventional vehicles – also leads to overall cost savings. Hence, taxi fleets, with an average daily mileage of 200 inner-city kilometres, are an attractive target group.

There are two possible charging systems for electric taxis (e-taxis), conventional fast charging stations and inductive wireless charging systems at taxi ranks. Fast charging stations have the disadvantage that the queueing at the taxi rank, especially in mixed fleets, is challenging as the e-taxi cannot move during the charging process. Inductive systems can be installed below the whole queuing space of the taxi rank and allow the usual queueing process even in mixed taxi fleets. A drawback is, however, a limited charging rate and a lower charging efficiency.

We have an existing simulation model of (electric) taxi movements in a German city. We will extend this simulation to ensure it realistically captures e-taxi operations. We will then develop a simulation-optimisation approach to identify the optimal locations for charging stations within this simulated city. This allows us to identify best value-for-money distributions of chargers and also to investigate questions such as what type of chargers and charging rates are required at different locations. As part of this project we can also add visualisation capability to the simulation.


## Animation output

 **The loader will load like this**

![Animation](https://github.com/Jash-2000/Simulation_Optimization_of_wireless_charging_station_locations_for_electric_taxis/blob/main/Images/Loader.gif)


**And finally, the full animation video would look like this : ** 
  
  https://user-images.githubusercontent.com/47540320/110109352-4f7b8a80-7dd3-11eb-8b31-fb0394fc59a8.mp4

  If the above file doesnt work, download the mp4 file from [here](https://github.com/Jash-2000/Simulation_Optimization_of_wireless_charging_station_locations_for_electric_taxis/blob/main/Images/Taxis.mp4)

**The corresponding section contains the actual Readme.md for our project but, you won't be able to exetute the project with the provided commands.**

---

# Simulation-Optimization of wireless charging station locations for electric taxis

The current version of the script has been tested in Julia version 1.5.2 and 1.5.3.  
It is importanat to note that JLD2 file system is used from Julia 1.5+ version(currently tested with JLD2). For older versions, consider using the code files present in **__JLD_files__** folder. 

Other instructions given below hold true for all versions (uptil the tested version).

## Instructions for Running the code (it may be quite slow to run as it initially reads in a lot of data):

**It is important to note that Julia REPL saves all the variables and constants that are defined/used during a session. Hence, every time you run the code, you have to open a new REPL terminal.**  

This project has 2 major components i.e. simulation and animation. Both these components can be executed by running the main.jl file with the following commands:

   1. In linux terminal:
        $ julia main_simulation.jl

   2. In julia terminal (REPL):
        julia> include("main.jl")

   3. In code editors supporting Julia Plugins (VS Code or JUNO-Atom):
       * File -> Open Folder -> evrouting
       * Comment the " path " script in main.jl
       * Open Julia terminal inside the editor. View the [Official documentation](https://www.julia-vscode.org/)for more help. 
       * Use julia main.jl or include("main.jl")


After a few moments, a Julia prompt will ask you whether you wish to see the animation or not. If you are interested in viewing just the simulation, type **"NO" or "no" or "N"**. But, in case you wish to see the animation as well, follow the additional instuctions provided in [Animation_Readme.md](https://github.com/Jash-2000/Simulation_Optimization_of_wireless_charging_station_locations_for_electric_taxis/blob/main/Animation_Readme.md).

---

## Files present in this folder
    
* **data.jl**	-	functions to load and store data (network, taxi trips)
* **energy.jl**  -   verious functions to compute SOC or time to reach certain SOC
* **main_simulation.jl**	-	main script to run simulation
* **main_animation.jl** - main script for running animation
* **routing.jl** - code to find taxi routes
* **TaxiSim.jl** -	taxi simulation main functions
* **types.jl**	  -  defines data structures
* **parameters.jl** - To initialize the parameters
* **animation.jl** - This file along with index.html can be used to animate the simulation.

Description of files present in __data__ folder is available in "Project files.txt". This folder primarily contains all the dataset and map(lat-long) that we have obtained/assumed. 

The folder __preprocessing__ primarily contains **__to be added__**.

--- 

## Extra Dependencies used

* **CSV module** - A fast, flexible delimited file reader/writer for Julia.

* **DataFrame module** - Pandas equivalent in Julia. Useful to manage bigdata. 
    
* **Dates module** - Used to perform precise operations on dates and time. 
    
* **JLD2 module** - JLD2 saves and loads Julia data structures in a format comprising a subset of HDF5, without any dependency on the HDF5 C library. It uses @load and @save methods to read and write the data structures. For loading all the variables use just @load <filename>. For more information of this and the next module, click [here](https://juliapackages.com/p/jld2).
    
* **FileIO module** - This module is used for basic file inout-output functions. It uses "load" and "save" methods. All the data is stored as dictionary of variable name and the variable itself. 
    
* **Parameters module** - Types with default field values, keyword constructors and (un-)pack macros. For more information, click [here](https://juliaobserver.com/packages/Parameters).
    
* **ResumableFunctions module**  - This module defines @resumable and @yield macros that ease the process of forming iterator. The macro @resumable transform a function definition into a finite state-machine, i.e. a callable type holding the state and references to the internal variables of the function and a constructor for this new type respecting the method signature of the original function definition. A very good example is present in [this](https://benlauwens.github.io/ResumableFunctions.jl/stable/) link
    
* **SimJulia module** - SimJulia is a discrete-event simulation library. The behavior of active components is modeled with **"processes"**. All processes live in an **"environment"**. They interact with the environment and with each other via "**events"**. For more information, click [here](https://simjuliajl.readthedocs.io/en/stable/welcome.html).
    
* **SparseArrays module** - Numpy equivalent in Julia. Basically used for performing matrix operations with ease.

* **JSON module** - Useful in serializing - deserializing Julia objects to JSON equivalents. 

--- 

## Before running
Update and uncomment the path at the top of main.jl to current location of julia code folder ( specifically, to the path where TaxiSim.jl is located). 

P.S - Skip this step if you are using a code editor and have followed the steps explained in the previous section. In this case, make sure that you have other dependencies installed in the same folder as well.  


---

## Common sources of error

Initial errors when trying to run may indicate that julia packages are missing.
For example one can get the following error for the missing a package 

```
   ERROR : LoadError: ArgumentError: Package CSV not found in current path:
```

For resolving the same, run the following code cell (The example show resolving the error for CSV module). 

```julia
    import Pkg
    Pkg.add("CSV")  # To install the CSV package.
    Pkg.test("CSV")    # Checking any package. 
```

---

## Viewing JLD2 files

The JLD2 files can be easily viewed using FileIO module. The files are loaded in the form of a dictionary. For example, if one wants to read the data present in  **network-karlsruhe.jld2** write the following script in Julia REPL:

```julia
     cd("C:/Users/Jash Shah/Desktop/evrouting/wireless_charging/data")
     using FileIO
     new_dict = load("network-karlsruhe.jld2")
     print(typeof(new_dict))
```

---

## To Implement Pre-compute Trips

This function should only be called once(i.e. at the start of simulation for the first time). Also, if the file __trips-karlsruhe__ is already present, avoid this step. 

The following code must be run to execute precompute_trips() function:

```julia
     sim = Simulation()
     net = load_network()
     data, ~, ~ = load_data(sim)

     @time precompute_trips(net, data, 1, 3800)
```
Here, 1 and 3800 are the starting and ending index of the calls as per in calls-karlsruhe.csv. Note that this is just an example of precomputing 3800 trips.

---

## Viewing the Log files 

Run the following code 

```julia
     using FileIO
     using JLD2
     jld = load(joinpath("data", "log-karlsruhe.jld2"))
     LOG = jld["log"]
```
