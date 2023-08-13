# For convenient graph data structures
using Graphs

# For discrete event simulation
using ResumableFunctions
using ConcurrentSim
import Base: put!, take!

# Useful for interactive work
# Enables automatic re-compilation of modified codes
using Revise

# The workhorse for the simulation
using QuantumSavory

# Predefined useful circuits
using QuantumSavory.CircuitZoo: EntanglementSwap, Purify2to1

include("channel.jl")

const perfect_pair = (Z1⊗Z1 + Z2⊗Z2) / sqrt(2)
const perfect_pair_dm = SProjector(perfect_pair)
const mixed_dm = MixedState(perfect_pair_dm)
noisy_pair_func(F) = F*perfect_pair_dm + (1-F)*mixed_dm # TODO make a depolarization helper
noisy_pair = noisy_pair_func(0.5)

# ENTANGLEMENT messages
@enum Messages begin
    FIND_QUBIT_TO_PAIR = 1
    ASSIGN_ORIGIN = 2
    INITIALIZE_STATE = 3
    LOCK = 4
    UNLOCK = 5
    ASSIGN = 6
    GENERATED_ENTANGLEMENT = 7
end

Base.show(io::IO, f::Messages) = print(io, RED_FG(@sprintf("%.3f",f)))


function findfreequbit(network, node)
    register = network[node]
    regsize = nsubsystems(register)
    findfirst(i->!isassigned(register,i) && !islocked(register[i]), 1:regsize)
end

function simulation_setup(sizes, commtimes)
    registers = Register[]
    for s in sizes
        push!(registers, Register(s))
    end

    graph = grid([length(sizes)]) # TODO: add as parameter so people can choose graph
    network = RegisterNet(graph, registers)
    sim = get_time_tracker(network)

    # Set up the all channels communicating between nodes
    for (;src, dst) in edges(network)
        network[(src, dst), :channel] = [DelayQueue(sim, 0.1) for i in 1:2]
    end

    # Set up the all channels that communicate when an action was finished: e.g. entanglemnt/purifiation
    for (;src, dst) in edges(network)
        network[(src, dst), :process_channel] = [DelayQueue(sim, 0.1) for i in 1:2]
    end
    
    for v in vertices(network)
        # Create an array specifying whether a qubit is entangled with another qubit
        network[v,:enttrackers] = Any[nothing for i in 1:sizes[v]]
    end

    sim, network
end

@resumable function freequbit_trigger(env::Simulation, network, node, remotenode, waittime=0., busytime=0.)
    way = node < remotenode ? 1 : 2
    channel = network[(node, remotenode), :channel][way]
    remote_channel = network[(node, remotenode), :channel][3 - way]
    while true
        i = findfreequbit(network, node)
        if isnothing(i)
            @yield timeout(sim, waittime)
            continue
        end

        @yield request(network[node][i])
        println("$(now(env)) :: $node > [trig] Locked $(node):$(i)")

        @yield timeout(sim, busytime)
        put!(channel, (FIND_QUBIT_TO_PAIR, i, -1)) # signal the free index found
    end
end

@resumable function receiver(env::Simulation, network, node, remotenode, waittime=0., busytime=0.)
    way = node < remotenode ? 1 : 2
    channel = network[(node, remotenode), :channel][way]
    remote_channel = network[(node, remotenode), :channel][3 - way]

    while true
        rec = @yield take!(remote_channel)
        msg, remote_i, i = rec[1], rec[2], rec[3]
        println("$(now(env)) :: $node received message $msg from $remotenode:$remote_i")
        if msg == FIND_QUBIT_TO_PAIR            
            i = findfreequbit(network, node)
            if isnothing(i)
                println("$(now(env)) :: $node > Nothing found at $node. Unlocking $remotenode:$remote_i")
                put!(channel, (UNLOCK, i, remote_i))
                continue
            end
            # lock slot
            @yield request(network[node][i])
            @yield timeout(sim, busytime)
            # assign slot
            network[node,:enttrackers][i] = (remotenode,remote_i)
            put!(channel, (ASSIGN_ORIGIN, i, remote_i))
        elseif msg == INITIALIZE_STATE
            initialize!((network[node][i], network[remotenode][remote_i]),noisy_pair; time=now(sim))
            println("$(now(env)) :: $node > Paired \t\t\t\t$node:$i, $remotenode:$remote_i")
            unlock(network[node][i])
            put!(channel, (UNLOCK, i, remote_i))
            @yield timeout(sim, busytime)
            # send that entanglement got generated
            put!(channel, (GENERATED_ENTANGLEMENT, i, remote_i))
        elseif msg == UNLOCK
            unlock(network[node][i])
            @yield timeout(sim, waittime)
        elseif msg == LOCK
            @yield request(network[node][i])
            @yield timeout(sim, busytime)
        end
    end
end

@resumable function sender(env::Simulation, network, node, remotenode, waittime=0., busytime=0.)
    way = node < remotenode ? 1 : 2
    channel = network[(node, remotenode), :channel][way]
    remote_channel = network[(node, remotenode), :channel][3 - way]

    while true
        rec = @yield take!(remote_channel)
        msg, remote_i, i = rec[1], rec[2], rec[3]
        if msg == ASSIGN_ORIGIN
            println("$(now(env)) :: $node > Pairing $node:$i, $remotenode:$remote_i")
            network[node,:enttrackers][i] = (remotenode,remote_i)
            put!(channel, (INITIALIZE_STATE, i, remote_i))
        elseif msg == UNLOCK
            unlock(network[node][i])
            @yield timeout(sim, waittime)
        elseif msg == LOCK
            @yield request(network[node][i])
            @yield timeout(sim, busytime)
        elseif msg == GENERATED_ENTANGLEMENT
            process_channel = network[(node, remotenode), :process_channel][way]
            # reroute the message to the process channel
            put!(process_channel, (GENERATED_ENTANGLEMENT, i, remote_i))
        end
    end
end

# listening on process channel
@resumable function purifier(env::Simulation, network, node, remotenode, waittime=0., busytime=0.)
    way = node < remotenode ? 1 : 2
    channel = network[(node, remotenode), :channel][way]
    remote_channel = network[(node, remotenode), :channel][3 - way]
    remote_process_channel = network[(node, remotenode), :process_channel][3 - way]

    indices = []
    remoteindices = []
    purif_circuit_size = 2

    while true
        rec = @yield take!(remote_process_channel)
        msg, remote_i, i = rec[1], rec[2], rec[3]
        push!(indices, i)
        push!(remoteindices, i)
        println("$(now(env)) PROCESS_CHANNEL :: $node:$i received message $msg from $remotenode:$remote_i")

        if msg == GENERATED_ENTANGLEMENT
            # begin purification process
            # lock current node and request locking of the orher
            @yield request(network[node][i])
            @yield timeout(sim, busytime)
            put!(channel, (LOCK, i, remote_i))

            println("$(now(env)) :: $node > \t\tLocked $node:$i, $remotenode:$remote_i; Indices Queue: $indices, $remoteindices")

            if length(indices) == purif_circuit_size
                println("PURIFICATION : Tupled pairs: $node:$indices, $remotenode:$remoteindices; Preparing for purification")
                # begin purif
                indices = []
                remoteindices = []
            end
        end
    end
end
