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

# ENTANGLEMENT

function findfreequbit(network, node)
    register = network[node]
    regsize = nsubsystems(register)
    findfirst(i->!isassigned(register,i) && !islocked(register[i]), 1:regsize)
end

@resumable function signalfreequbit(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    @yield timeout(sim, waittime)
    while true
        entid = rand(Float16)
        i = findfreequbit(network, node)
        if isnothing(i)
            @yield timeout(sim, waittime)
            @simlog env "id:$entid&m:NTHS       $node] @ $(now(env))\t> Signal failed: Nothing found in node [$node]"
            continue
        end

        @yield request(network[node][i])
        @yield timeout(sim, busytime)

        value = Dict(:time=>now(env), :node=>node, :index=>i, :i=>i, :message=>1, :entid=>entid)
        put!(channel, value, 1) # [1] -- found free at sender
    end
end

@resumable function findfreequbitresp(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msg = @yield take!(channel, 1) # [1]

        if msg[:node] == node
            put!(channel, msg, 1)
            continue
        end

        ## BEGIN REDO
        if msg[:node] < node
            unlock(network[msg[:node]][msg[:i]])
            @simlog env "\nid:$(msg[:entid]) CANCELED MESSG NODES $node:$(msg[:i]), $(msg[:node])"
            continue
        end
        ## END REDO

        @simlog env "\nid:$(msg[:entid])&m:FNDS [ ENT  ] > Entangler triggered at $(msg[:time]), node [$(msg[:node]):$(msg[:i])]\t\t | (msg=$(msg[:message]))"
        @simlog env "id:$(msg[:entid])&m:____ [$node <- $(msg[:node])] @ $(now(env))\t> Free at $(msg[:node]):$(msg[:index]). Requesting node $node"
        @simlog env "id:$(msg[:entid])&m:____       $node] @ $(now(env))\t> Searching in node [$node]"

        i = findfreequbit(network, node)
        if isnothing(i)
            @simlog env "id:$(msg[:entid])&m:NTHR       $node] @ $(now(env))\t> Nothing found in node [$node]"
            @yield timeout(sim, waittime)

            # TODO: send message to sender to unlock itself []
            unlock(network[msg[:node]][msg[:index]])
            @simlog env "id:$(msg[:entid])&m:UNLK       $node] @ $(now(env))\t> Unlocked $(msg[:node]):$(msg[:index])"
            continue
        end
        
        @yield request(network[node][i])
        @yield timeout(sim, busytime)
        @simlog env "id:$(msg[:entid])&m:FNDR       $node] @ $(now(env))\t> Found $(node):$i"

        # Assign the qubit
        network[node,:enttrackers][i] = (msg[:node],msg[:index])

        value = Dict(:time=>now(env), :node=>node, :target=>msg[:node], :index=>i, :i=>msg[:index], :message=>2, :entid=>msg[:entid])
        put!(channel, value, 2) # [2] -- found free at receiver
    end
end

@resumable function assignqubit(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msg = @yield take!(channel, 2) # [2]
        
        # if not intended for me , reroute the message and wait
        if msg[:target] != node
            put!(channel, msg, 2)
            continue
        end

        i = msg[:i]
        @simlog env "id:$(msg[:entid])&m:ASGR [$node <- $(msg[:node])] @ $(now(env))\t> Assigned $(msg[:node]):$(msg[:index]) to $node:$i\t\t | (msg=$(msg[:message]))"

        # Assign the qubit
        network[node,:enttrackers][i] = (msg[:node],msg[:index])

        value = Dict(:time=>now(env), :node=>node, :target=>msg[:node], :index=>i, :i=>msg[:index], :message=>3, :entid=>msg[:entid])
        put!(channel, value, 3)
    end
end

@resumable function assignqubitback(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msg = @yield take!(channel, 3) # [3]

        # if not intended for me , reroute the message and wait
        if msg[:target] != node
            put!(channel, msg, 3)
            continue
        end

        i = msg[:i]
        @simlog env "id:$(msg[:entid])&m:ASGS [$node <- $(msg[:node])] @ $(now(env))\t> Assigned $(msg[:node]):$(msg[:index]) to $node:$i\t\t | (msg=$(msg[:message]))"

        initialize!((network[node][i],network[msg[:node]][msg[:index]]),noisy_pair; time=now(sim))
        # initialize [find a way to do this locally using another node??]
        @simlog env "id:$(msg[:entid])&m:ENT% [$node: $(msg[:node]),$node] @ $(now(env))\t> Entangled node $(node):$(i) and node $(msg[:node]):$(msg[:index])"
        
        # Log succesfull entanglement
        entanglement_status[msg[:entid]] = EntInfo([[node, i], [msg[:node], msg[:index]]])
        entanglement_status[msg[:entid]].sim = env
        stamp!(entanglement_status[msg[:entid]], :ENT)

        unlock(network[node][i])

        value = Dict(:time=>now(env), :node=>node, :target=>msg[:node], :index=>i, :i=>msg[:index], :message=>3, :entid=>msg[:entid])
        put!(channel, value, 4)

        # TODO: Sen message to sender to purify it's self
    end
end

@resumable function waitandunlocklistener(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msg = @yield take!(channel, 4)

        # if not intended for me , reroute the message and wait
        if msg[:target] != node
            put!(channel, msg, 4)
            continue
        end

        unlock(network[node][msg[:i]])
        @simlog env "id:$(msg[:entid])&m:UNL% [$node: $(msg[:node]),$node] @ $(now(env))\t> Unlocked $(node):$(msg[:i]) and node $(msg[:node]):$(msg[:index])"

        value = Dict(:time=>now(env), :node=>node, :target=>msg[:node], :index=>msg[:i],:i=>msg[:index], :message=>5, :entid=>msg[:entid])
        put!(channel, value, 5)
    end
end
# PURIFICATION
@resumable function purify_getready(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msg = @yield take!(channel, 5)
        nodes = [msg[:node], msg[:target]]
        indices = [msg[:index], msg[:i]]

        if node in nodes
            node2 = nodes[1]
            index2 = indices[1]
            index = indices[2]
            if node == nodes[1]
                node2 = nodes[2]
                index2 = indices[2]
                index = indices[1]
            end

            @simlog env "id:$(msg[:entid])&p:PURF       $node] @ $(now(env))\t> Request to purify $(node):$index and $node2:$index2 receivedat $node"

            # check if self is locked
            if islocked(network[node][index])
                @simlog env "id:$(msg[:entid])&p:SLOK       $node] @ $(now(env))\t> FAILED: Request to purify $(node):$index and $node2:$index2 failed, SLOT LOCKED"
                @yield timeout(sim, waittime)

                put!(channel, msg, 5)
                continue
            end

            # lock self
            @yield request(network[node][index])
            @yield timeout(sim, busytime)

            value = Dict(:time=>now(env), :node=>node, :target=>node2, :index=>index2,:i=>index, :message=>6, :entid=>msg[:entid])
            put!(channel, value, 6) # confirm entanglement and request lock from frined
            @simlog env "id:$(msg[:entid])&p:EVN6     $node] @ $(now(env))\t> Requested friend lock $node2:$index2"

        else
            put!(channel, msg, 5)
        end
    end
end

@resumable function purify_confirm(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msg = @yield take!(channel, 6)
        if node == msg[:target]
            index = msg[:index]
            @simlog env "id:$(msg[:entid])&p:LOK1       $node] @ $(now(env))\t> Node locked and requested locking from me..."

            # check if self is locked
            if islocked(network[node][index])
                @yield timeout(sim, waittime)
                put!(channel, msg, 6)
                continue
            end

            # lock self
            @yield request(network[node][index])
            @yield timeout(sim, busytime)

            @simlog env "id:$(msg[:entid])&p:LOK2       $node] @ $(now(env))\t> Nodes $(msg[:node]):$(msg[:index]), $(msg[:target]):$(msg[:i]) locked succesfully"
            @simlog env "id:$(msg[:entid])&p:____       $node] @ $(now(env))\t> Perceiding with purifLeft on $node:$index"


            value = Dict(:time=>now(env), :node=>node, :target=>msg[:node], :index=>msg[:i],:i=>index, :message=>7, :entid=>msg[:entid])
            put!(channel, value, 7) # signal the confirmation of a pair

        else
            put!(channel, msg, 6)
        end
    end
end

@resumable function purify_expect(env::Simulation, network, channel::Channel, node, waittime=0., busytime=0.)
    while true
        msgf = @yield take!(channel, 7)
        if node == msgf[:target]
            node2 = msgf[:node]
            indices = [msgf[:i], msgf[:index]]
            msg = @yield take!(channel, 7)
            if (node == msg[:node] && node2 == msg[:target]) || 
                (node2 == msg[:node] && node == msg[:target])
                indices2 = [msg[:i], msg[:index]]

                @simlog env "id:$(msg[:entid])&p:PAIR       $node] @ $(now(env))\t> Paired {$node:$(indices[1]), $node2:$(indices[2])} and {$node:$(indices2[1]), $node2:$(indices2[2])}."
                stamp!(entanglement_status[msg[:entid]], :PAIR, "$(msg[:entid]) paired with $(msgf[:entid])")
                stamp!(entanglement_status[msgf[:entid]], :PAIR, "$(msgf[:entid]) paired with $(msg[:entid])")

            else
                put!(channel, msg, 7)
            end
        else
            put!(channel, msg, 7)
        end
    end
end

function simulation_setup(sizeA, sizeB, commtimes)
    registers = Register[]
    push!(registers, Register(sizeA))
    push!(registers, Register(sizeB))
    sizes = [sizeA, sizeB]


    graph = grid([2])
    network = RegisterNet(graph, registers)
    sim = get_time_tracker(network)

    # Set up the chhannel communicating between nodes 1 and 2
    network[(1, 2), :channel] = [Channel(sim, commtimes[i], 20) for i in 1:2]

    for v in vertices(network)
        # Create an array specifying whether a qubit is entangled with another qubit
        network[v,:enttrackers] = Any[nothing for i in 1:sizes[v]]
    end

    sim, network
end
