include("setup.jl")

using GLMakie # For plotting
GLMakie.activate!()

# Configuration variables
PURIFICATION = true                 # if true, purification is also performed
console = false                     # if true, the program will not produce a vide file
time = 20.3                         # time to run the simulation
commtimes = [0.2, 0.14]             # communication times from sender->receiver, and receiver->sender
registersizes = [4, 5, 6, 4]               # sizes of the registers
node_timedelay = [0.4, 0.3]         # waittime and busytime for processes
noisy_pair = noisy_pair_func(0.7)   # noisy pair
# Simulation and Network
sim, network = simulation_setup(registersizes, commtimes)


# Setting up the ENTANGMELENT protocol
for (;src, dst) in edges(network)
    @process freequbit_trigger(sim, network, src, dst, node_timedelay[1], node_timedelay[2])
    @process entangle(sim, network, src, dst, node_timedelay[1], node_timedelay[2])
    @process entangle(sim, network, dst, src, node_timedelay[1], node_timedelay[2])
end
# Setting up the purification protocol 
if PURIFICATION
    for (;src, dst) in edges(network)
        @process purifier(sim, network, src, dst, node_timedelay[1], node_timedelay[2], false)
        @process purifier(sim, network, dst, src, node_timedelay[1], node_timedelay[2], false)
    end
end
# Running the simulation
if console
    run(sim, time)
else
    # set up a plot and save a handle to the plot observable
    fig = Figure(resolution=(400,400))
    _,ax,_,obs = registernetplot_axis(fig[1,1],network)
    display(fig)

    # record the simulation progress
    step_ts = range(0, time, step=0.1)
    record(fig, "1_firstgenrepeater_$(length(registersizes))nodes.$(PURIFICATION ? "entpurif$(USE)to1" : "entonly").mp4", step_ts, framerate=10, visible=true) do t
        run(sim, t)
        notify(obs)
        ax.title = "t=$(t)"
    end
end