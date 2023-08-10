include("setup.jl")

commtimes = [0.2, 0.14]
sim, network = simulation_setup(8, 4, commtimes)
node_timedelay = [0.4, 0.3]
noisy_pair = noisy_pair_func(0.5)
for (;src, dst) in edges(network)
    chn = network[(src, dst), :channel]
    @process sender_signalfreequbit(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process sender_waitforfreequbitback(sim, network, chn[1], src, node_timedelay[1], node_timedelay[2])
    @process receiver_findfreequbit(sim, network, chn[1], dst, node_timedelay[1], node_timedelay[2])
    @process receiver_assignfoundqubit(sim, network, chn[1], dst, node_timedelay[1], node_timedelay[2])
end


run(sim, 10.)

println()
for item in entanglement_status
    print(item.first)
    print(" \t: ")
    println(item.second)
end