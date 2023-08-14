using Printf
Base.show(io::IO, f::Float16) = print(io, RED_FG(@sprintf("%.3f",f)))
Base.show(io::IO, f::Float64) = print(io, GREEN_FG(@sprintf("%.3f",f)))
using Crayons
using Crayons.Box
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

const perfect_pair = (Z1⊗Z1 + Z2⊗Z2) / sqrt(2)
const perfect_pair_dm = SProjector(perfect_pair)
const mixed_dm = MixedState(perfect_pair_dm)
noisy_pair_func(F) = F*perfect_pair_dm + (1-F)*mixed_dm # TODO make a depolarization helper
noisy_pair = noisy_pair_func(0.5)

# ENTANGLEMENT/PURIFICATION messages
@enum Messages begin
    FIND_QUBIT_TO_PAIR = 1
    ASSIGN_ORIGIN = 2
    INITIALIZE_STATE = 3
    LOCK = 4
    UNLOCK = 5
    ASSIGN = 6
    GENERATED_ENTANGLEMENT = 7
    PURIFY = 8
    REPORT_SUCCESS = 9
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

# the trigger which triggers the entanglement start
@resumable function freequbit_trigger(env::Simulation, network, node, remotenode, waittime=0., busytime=0.)
    way = node < remotenode ? 1 : 2
    channel = network[(node, remotenode), :channel][way]
    remote_channel = network[(node, remotenode), :channel][3 - way]
    # TODO: make the assignment of channeld directional so the 3 lines above are not needed
    while true
        println("[SEARCHING] $(now(env)) :: $node")

        i = findfreequbit(network, node)
        if isnothing(i)
            @yield timeout(sim, waittime)
            continue
        end

        @yield request(network[node][i])
        println("[ENTANGLER TRIGGERED] $(now(env)) :: $node > [trig] Locked $(node):$(i)")
        @yield timeout(sim, busytime)
        put!(channel, (FIND_QUBIT_TO_PAIR, i, -1))
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
            @yield request(network[node][i])
            @yield timeout(sim, busytime)
            network[node,:enttrackers][i] = (remotenode,remote_i)
            put!(channel, (ASSIGN_ORIGIN, i, remote_i))
        elseif msg == INITIALIZE_STATE
            initialize!((network[node][i], network[remotenode][remote_i]),noisy_pair; time=now(sim))
            println("$(now(env)) :: $node > Paired \t\t\t\t$node:$i, $remotenode:$remote_i")
            unlock(network[node][i])
            put!(channel, (UNLOCK, i, remote_i))
            @yield timeout(sim, busytime)
            # signal that entanglement got generated
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
        println("$(now(env)) :: $node received message $msg from $remotenode:$remote_i")

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

function purify2to1(rega, regb)
    apply!((regb, rega), CNOT)
    meas = project_traceout!(regb, σˣ)
    meas
end

# listening on process channel
@resumable function purifier(env::Simulation, network, node, remotenode, waittime=0., busytime=0.)
    way = node < remotenode ? 1 : 2
    channel = network[(node, remotenode), :channel][way]
    process_channel = network[(node, remotenode), :process_channel][way]
    remote_channel = network[(node, remotenode), :channel][3 - way]
    remote_process_channel = network[(node, remotenode), :process_channel][3 - way]

    indicesg = []
    remoteindicesg = []
    purif_circuit_size = 2

    while true
        rec = @yield take!(remote_process_channel)
        msg, remote_i, i = rec[1], rec[2], rec[3]
        println("$(now(env)) PROCESS_CHANNEL :: $node:$i received message $msg from $remotenode:$remote_i")

        if msg == GENERATED_ENTANGLEMENT
            # begin purification process
            # lock current node and request locking of the orher
            push!(indicesg, i)
            push!(remoteindicesg, remote_i)
            @yield request(network[node][i])
            @yield timeout(sim, busytime)
            put!(channel, (LOCK, i, remote_i))

            println("$(now(env)) :: $node > \t\tLocked $node:$i, $remotenode:$remote_i; Indices Queue: $indicesg, $remoteindicesg")

            if length(indicesg) == purif_circuit_size
                println("PURIFICATION : Tupled pairs: $node:$indicesg, $remotenode:$remoteindicesg; Preparing for purification")
                # begin purification of self
                slots = [network[node][x] for x in indicesg]
                println(slots)
                local_measurement = purify2to1(slots...)
                # send message to other node to purify
                put!(process_channel, (PURIFY, local_measurement, [remoteindicesg, indicesg]))
                indicesg = []
                remoteindicesg = []
            end
        elseif msg == PURIFY
            indices = i[1]
            remoteindices = i[2]
            remote_measurement = remote_i
            slots = [network[node][x] for x in indices]
            println(slots)

            local_measurement = purify2to1(slots...)
            success = local_measurement == remote_measurement
            put!(process_channel, (REPORT_SUCCESS, success, [remoteindices, indices]))
            if !success
                println("$(now(env)) :: PURIFICATION FAILED @ $node:$indices, $remotenode:$remoteindices")
                (traceout!(indices[i]) for i in 2:purif_circuit_size)
                network[node,:enttrackers][indices[1]] = nothing
            end
            (network[node,:enttrackers][indices[i]] = nothing for i in 2:purif_circuit_size)
            release.(network[node][indices])
            println("$(now(env)) :: PURIFICATION SUCCEDED @ $node:$indices, $remotenode:$remoteindices\n")

        elseif msg == REPORT_SUCCESS
            success = remote_i
            indices = i[1]
            if !success
                (traceout!(indices[i]) for i in 2:purif_circuit_size)
                network[node,:enttrackers][indices[1]] = nothing
            end
            (network[node,:enttrackers][indices[i]] = nothing for i in 2:purif_circuit_size)
            release.(network[node][indices])

            # TODO: OPTION: Here we have a choice. We can either leave it as such, or signal anouther entanglement generation to the simple channel
        end
    end
end
