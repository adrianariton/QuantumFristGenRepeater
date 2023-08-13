include("2_setup.jl")

using GLMakie # For plotting
GLMakie.activate!()

console = false
time = 20.3
commtimes = [0.2, 0.14]
sim, network = simulation_setup([4, 5, 6], commtimes)
node_timedelay = [0.4, 0.3]
noisy_pair = noisy_pair_func(0.5)
chn = Channel(sim, commtimes[1], 20) # 20 thread channel
for src in vertices(network)
    @process signalfreequbit(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
    @process assignqubit(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
    @process waitandunlocklistener(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
    
    @process findfreequbitresp(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
    @process assignqubitback(sim, network, chn, src, node_timedelay[1], node_timedelay[2])

    @process listenforunlock(sim, network, chn, src, node_timedelay[1], node_timedelay[2])

end

for src in vertices(network)
    @process purify_getready(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
    @process purify_confirm(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
    @process purify_expect(sim, network, chn, src, node_timedelay[1], node_timedelay[2])
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
    record(fig, "2_firstgenrepeater.entpurif.mp4", step_ts, framerate=10, visible=true) do t
        run(sim, t)
        notify(obs)
        ax.title = "t=$(t)"
    end
end
println()
println("Reuslts: \n")
for item in entanglement_status
    print(RED_FG("id:$(item.first)"))
    print(" \t: ")
    statusinfo(item.second)
    println()
end