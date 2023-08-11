include("setup.jl")

commtimes = [0.2, 0.14]
sim, network = simulation_setup(4, 5, commtimes)
node_timedelay = [0.4, 0.3]
noisy_pair = noisy_pair_func(0.5)

chn = network[(1, 2), :channel]
for src in vertices(network)
    @process signalfreequbit(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process assignqubit(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process waitandunlocklistener(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])

    @process findfreequbitresp(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process assignqubitback(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])

end

chn = network[(1, 2), :channel]
for src in vertices(network)
    @process purify_getready(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process purify_confirm(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process purify_expect(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
end

run(sim, 20.3)

println()
println("Reuslts: \n")
for item in entanglement_status
    print(RED_FG("id:$(item.first)"))
    print(" \t: ")
    statusinfo(item.second)
    println()
end