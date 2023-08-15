include("1_setup.jl")

using GLMakie # For plotting
GLMakie.activate!()
PURIFICATION = true
console = false
time = 20.3
commtimes = [0.2, 0.14]
sim, network = simulation_setup([4,5], commtimes)
node_timedelay = [0.4, 0.3]
noisy_pair = noisy_pair_func(0.7)

# setting up the edge protocol
for (;src, dst) in edges(network)
    @process freequbit_trigger(sim, network, src, dst, node_timedelay[1], node_timedelay[2])
    @process sender(sim, network, src, dst, node_timedelay[1], node_timedelay[2])
    @process receiver(sim, network, dst, src, node_timedelay[1], node_timedelay[2])

    # @process freequbit_trigger(sim, network, dst, src, node_timedelay[1], node_timedelay[2])
    # @process sender(sim, network, dst, src, node_timedelay[1], node_timedelay[2])
    # @process receiver(sim, network, src, dst, node_timedelay[1], node_timedelay[2])
end
if PURIFICATION
    for (;src, dst) in edges(network)
        @process purifier(sim, network, src, dst, node_timedelay[1], node_timedelay[2], false)
        @process purifier(sim, network, dst, src, node_timedelay[1], node_timedelay[2], false)
    end
end

if console
    run(sim, time)
else
    # set up a plot and save a handle to the plot observable
    fig = Figure(resolution=(400,400))
    _,ax,_,obs = registernetplot_axis(fig[1,1],network)
    display(fig)

    # record the simulation progress
    step_ts = range(0, time, step=0.1)
    record(fig, "1_firstgenrepeater$time.$(PURIFICATION ? "entpurif" : "ent").mp4", step_ts, framerate=10, visible=true) do t
        run(sim, t)
        notify(obs)
        ax.title = "t=$(t)"
    end
end