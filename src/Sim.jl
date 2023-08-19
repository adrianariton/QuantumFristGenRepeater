using Base.Threads
using WGLMakie
WGLMakie.activate!()
using JSServe
using Markdown

# 1. LOAD LAYOUT HELPER FUNCTION AND UTILSm    
using CSSMakieLayout
include("setup.jl")

## config sizes TODO: make linear w.r.t screen size
# Change between color schemes by uncommentinh lines 17-18
retina_scale = 2
config = Dict(
    :resolution => (retina_scale*1400, retina_scale*700), #used for the main figures
    :smallresolution => (280, 160), #used for the menufigures
    :colorscheme => ["rgb(242, 242, 247)", "black", "#000529", "white"]
    #:colorscheme => ["rgb(242, 242, 247)", "black", "rgb(242, 242, 247)", "black"]
)

obs_PURIFICATION = Observable(true)
obs_time = Observable(20.3)
obs_commtime = Observable(0.1)
obs_registersizes = Observable([4, 5])
obs_node_timedelay = Observable([0.4, 0.3])
obs_initial_prob = Observable(0.7)
obs_USE = Observable(3)
obs_emitonpurifsuccess = Observable(0)

purifcircuit = Dict(
    2=>purify2to1,
    3=>purify3to1
)


###################### 2. LAYOUT ######################
#   Returns the reactive (click events handled by zstack)
#   layout of the activefigure (mainfigure)
#   and menufigures (the small figures at the top which get
#   clicked)

function layout_content(DOM, mainfigures #TODO: remove DOM param
    , menufigures, title_zstack, session, active_index)
    
    menufigs_style = """
        display:flex;
        flex-direction: row;
        justify-content: space-around;
        background-color: $(config[:colorscheme][1]);
        padding-top: 20px;
        width: $(config[:resolution][1]/retina_scale)px;
    """
    menufigs_andtitles = wrap([
        vstack(
            hoverable(menufigures[i], anim=[:border], class="$(config[:colorscheme][2])";
                    stayactiveif=@lift($active_index == i)),
            title_zstack[i];
            class="justify-center align-center "    
            ) 
        for i in 1:3]; class="menufigs", style=menufigs_style)
   
    activefig = zstack(
                active(mainfigures[1]),
                wrap(mainfigures[2]),
                wrap(mainfigures[3]);
                activeidx=active_index,
                anim=[:whoop],
                style="width: $(config[:resolution][1]/retina_scale)px")
    
    content = Dict(
        :activefig => activefig,
        :menufigs => menufigs_andtitles
    )
    return DOM.div(menufigs_andtitles, CSSMakieLayout.formatstyle, activefig), content

end

###################### 3. PLOT FUNCTIONS ######################
#   These are used to configure each figure from the layout,
#   meaning both the menufigures and the mainfigures.
#   One can use either on whatever figure, but for the purpose
#   of this project, they will be used as such
#       |   plot_alphafig - for the first figure (Entanglement Generation)
#       |   plot_betafig - for the second figure (Entanglement Swapping)
#       |   plot_gammafig - for the third figure (Entanglement Purification)
#   , as one can see in the plot(figure_array, metas) function.


function plot_alphafig(F, meta=""; hidedecor=false)
    PURIFICATION = obs_PURIFICATION[]
    time = obs_time[]
    commtimes = [obs_commtime[], obs_commtime[]]
    registersizes = obs_registersizes[]
    node_timedelay = obs_node_timedelay[]
    initial_prob = obs_initial_prob[]
    USE = obs_USE[]
    noisy_pair = noisy_pair_func(initial_prob[])
    emitonpurifsuccess = obs_emitonpurifsuccess[]==1

    protocol = FreeQubitTriggerProtocolSimulation(USE, purifcircuit[USE], # purifcircuit
                                                node_timedelay[1], node_timedelay[2], # wait and busy times
                                                Dict(:simple_channel=>:channel,
                                                    :process_channel=>:process_channel), # keywords to store the 2 types of channels in the network
                                                emitonpurifsuccess) # emit on purifsucess
    sim, network = simulation_setup(registersizes, commtimes, protocol)
    _,ax,p,obs = registernetplot_axis(F[1:2,1:3],network; color2qubitlinks=true)

    if hidedecor
        return
    end

    F[3, 1:6] = buttongrid = GridLayout(tellwidth = false)
    running = Observable(false)
    buttongrid[1,1] = b = Makie.Button(F, label = @lift($running ? "Stop" : "Run"), fontsize=32)

    Colorbar(F[1:2, 3:4], limits = (0, 1), colormap = :Spectral,
    flipaxis = false)

    plotfig = F[2,4:6]
    fidax = Axis(plotfig[2:24, 2:24], title="Maximum Entanglement Fidelity", titlesize=32)

    subfig = F[1, 5:6]
    sg = SliderGrid(subfig,
    (label="time", range=3:0.1:30, startvalue=20.3),
    (label="circuit", range=2:3, startvalue=3),
    (label="1 - pauli error prob", range=0.5:0.1:0.9, startvalue=0.7),
    (label="chanel delay", range=0.1:0.1:0.3, startvalue=0.1),
    (label="recycle purif pairs", range=0:1, startvalue=0))
    observable_params = [obs_time, obs_USE, obs_initial_prob, obs_commtime, obs_emitonpurifsuccess]

    for i in 1:length(observable_params)
        on(sg.sliders[i].value) do val
            if !running[]
                observable_params[i][] = val
                notify(observable_params[i])
            end
        end
    end

    on(b.clicks) do _ 
        running[] = !running[]
    end

    on(running) do r
        if r
            PURIFICATION = obs_PURIFICATION[]
            time = obs_time[]
            commtimes = [obs_commtime[], obs_commtime[]]
            registersizes = obs_registersizes[]
            node_timedelay = obs_node_timedelay[]
            initial_prob = obs_initial_prob[]
            USE = obs_USE[]
            noisy_pair = noisy_pair_func(initial_prob[])
            emitonpurifsuccess = obs_emitonpurifsuccess[]==1

            protocol = FreeQubitTriggerProtocolSimulation(USE, purifcircuit[USE], # purifcircuit
                                                        node_timedelay[1], node_timedelay[2], # wait and busy times
                                                        Dict(:simple_channel=>:channel,
                                                            :process_channel=>:process_channel), # keywords to store the 2 types of channels in the network
                                                        emitonpurifsuccess) # emit on purif success
            sim, network = simulation_setup(registersizes, commtimes, protocol)
            _,ax,p,obs = registernetplot_axis(F[1:2,1:3],network; color2qubitlinks=true)

            
            currenttime = Observable(0.0)
            # Setting up the ENTANGMELENT protocol
            for (;src, dst) in edges(network)
                @process freequbit_trigger(sim, protocol, network, src, dst)
                @process entangle(sim, protocol, network, src, dst, noisy_pair)
                @process entangle(sim, protocol, network, dst, src, noisy_pair)
            end
            # Setting up the purification protocol 
            if PURIFICATION
                for (;src, dst) in edges(network)
                    @process purifier(sim, protocol, network, src, dst)
                    @process purifier(sim, protocol, network, dst, src)
                end
            end

            step_ts = range(0, time[], step=0.1)
            #run(sim, time[])

            coordsx = Float32[]
            maxcoordsy= Float32[]
            mincoordsy= Float32[]
            for t in 0:0.1:time
                currenttime[] = t
                run(sim, currenttime[])
                notify(obs)
                ax.title = "t=$(t)"
                if !running[]
                    break
                end
                if length(p[:fids][]) > 0
                    push!(coordsx, t)
                    push!(maxcoordsy, maximum(p[:fids][]))
                    empty!(fidax)
                    stairs!(fidax, coordsx, maxcoordsy, color=(emitonpurifsuccess ? :blue : :green), linewidth=3)
                end
            end
        else
            
            empty!(ax)
            ax.title=nothing
            sim, network = simulation_setup(registersizes, commtimes, protocol)
            _,ax,p,obs = registernetplot_axis(F[1:2,1:3],network; color2qubitlinks=true)

        end
    end
end

function plot_betafig(figure, meta=""; hidedecor=false)
    # This is where we will do the receipe for the second figure (Entanglement Swap)

    ax = Axis(figure[1, 1])
    scatter!(ax, [1,2], [2,3], color=(:black, 0.2))
    axx = Axis(figure[1, 2])
    scatter!(axx, [1,2], [2,3], color=(:black, 0.2))
    axxx = Axis(figure[2, 1:2])
    scatter!(axxx, [1,2], [2,3], color=(:black, 0.2))

    if hidedecor
        hidedecorations!(ax)
        hidedecorations!(axx)
        hidedecorations!(axxx)
    end
end

function plot_gammafig(figure, meta=""; hidedecor=false)
    # This is where we will do the receipe for the third figure (Entanglement Purif)

    ax = Axis(figure[1, 1])
    scatter!(ax, [1,2], [2,3], color=(:black, 0.2))

    if hidedecor
        hidedecorations!(ax)
    end
end

#   The plot function is used to prepare the receipe (plots) for
#   the mainfigures which get toggled by the identical figures in
#   the menu (the menufigures), as well as for the menufigures themselves

function plot(figure_array, metas=["", "", ""]; hidedecor=false)
    with_theme(fontsize=32) do
        plot_alphafig(figure_array[1], metas[1]; hidedecor=hidedecor)
        plot_betafig( figure_array[2], metas[2]; hidedecor=hidedecor)
        plot_gammafig(figure_array[3], metas[3]; hidedecor=hidedecor)
    end
end

###################### 4. LANDING PAGE OF THE APP ######################

landing = App() do session::Session

    # Create the menufigures and the mainfigures
    mainfigures = [Figure(backgroundcolor=:white,  resolution=config[:resolution]) for _ in 1:3]
    menufigures = [Figure(backgroundcolor=:white,  resolution=config[:smallresolution]) for _ in 1:3]
    titles= ["Entanglement Generation",
    "Entanglement Swapping",
    "Entanglement Purification"]
    # Active index: 1 2 or 3
    #   1: the first a.k.a alpha (Entanglement Generation) figure is active
    #   2: the second a.k.a beta (Entanglement Swapping) figure is active    
    #   3: the third a.k.a gamma (Entanglement Purification) figure is active
    activeidx = Observable(1)
    hoveredidx = Observable(0)

    # CLICK EVENT LISTENERS
    for i in 1:3
        on(events(menufigures[i]).mousebutton) do event
            activeidx[]=i  
            notify(activeidx)
        end
        on(events(menufigures[i]).mouseposition) do event
            hoveredidx[]=i  
            notify(hoveredidx)
        end
        
        # TODO: figure out when mouse leaves and set hoverableidx[] to 0
    end

    # Using the aforementioned plot function to plot for each figure array
    plot(mainfigures)
    plot(menufigures; hidedecor=true)

    
    # Create ZStacks displayong titles below the menu graphs
    titles_zstack = [zstack(wrap(DOM.h4(titles[i], class="upper")),
                            wrap(""); 
                            activeidx=@lift(($hoveredidx == i || $activeidx == i)),
                            anim=[:opacity], style="""color: $(config[:colorscheme][2]);""") for i in 1:3]



    # Obtain reactive layout of the figures
    
    layout, content = layout_content(DOM, mainfigures, menufigures, titles_zstack, session, activeidx)

    # Add title to the right in the form of a ZStack
    titles_div = [DOM.h1(t) for t in titles]
    titles_div[1] = active(titles_div[1])
    titles_div = zstack(titles_div; activeidx=activeidx, anim=[:static]
    , style="""color: $(config[:colorscheme][4]);""") # static = no animation
    
    
    return hstack(layout, hstack(titles_div; style="padding: 20px; margin-left: 10px;
                                background-color: $(config[:colorscheme][3]);"); style="width: 100%;")

end

landing2 = App() do session::Session

    # Active index: 1 2 or 3
    #   1: the first a.k.a alpha (Entanglement Generation) figure is active
    #   2: the second a.k.a beta (Entanglement Swapping) figure is active    
    #   3: the third a.k.a gamma (Entanglement Purification) figure is active
    activeidx = Observable(1)
    hoveredidx = Observable(0)

    # Create the buttons and the mainfigures
    mainfigures = [Figure(backgroundcolor=:white,  resolution=config[:resolution]) for _ in 1:3]
    buttonstyle = """
        background-color: $(config[:colorscheme][1]);
        color: $(config[:colorscheme][2]);
        border: none !important;
    """
    buttons = [modifier(wrap(DOM.h1("〈")); action=:decreasecap, parameter=activeidx, cap=3, style=buttonstyle),
                modifier(wrap(DOM.h1("〉")); action=:increasecap, parameter=activeidx, cap=3, style=buttonstyle)]
    
    # Titles of the plots
    titles= ["Entanglement Generation",
    "Entanglement Swapping",
    "Entanglement Purification"]
    

    # Using the aforementioned plot function to plot for each figure array
    plot(mainfigures)

    # Obtain the reactive layout
    activefig = zstack(
                active(mainfigures[1]),
                wrap(mainfigures[2]),
                wrap(mainfigures[3]);
                activeidx=activeidx,
                style="width: $(config[:resolution][1]/retina_scale)px")
    

    layout = hstack(buttons[1], activefig, buttons[2])
    # Add title to the right in the form of a ZStack
    titles_div = [DOM.h1(t) for t in titles]
    titles_div[1] = active(titles_div[1])
    titles_div = zstack(titles_div; activeidx=activeidx, anim=[:static],
                    style="""color: $(config[:colorscheme][4]);""") # static = no animation
    
    
    return hstack(CSSMakieLayout.formatstyle, layout, hstack(titles_div; style="padding: 20px;  margin-left: 10px;
                                background-color:  $(config[:colorscheme][3]);"); style="width: 100%;")

end

nav = App() do session::Session
    return vstack(DOM.a("LANDING", href="/1"), DOM.a("LANDING2", href="/2"))
end

##
# Serve the Makie app
isdefined(Main, :server) && close(server);
port = parse(Int, get(ENV, "QS_COLORCENTERMODCLUSTER_PORT", "8888"))
interface = get(ENV, "QS_COLORCENTERMODCLUSTER_IP", "127.0.0.1")
proxy_url = get(ENV, "QS_COLORCENTERMODCLUSTER_PROXY", "")
server = JSServe.Server(interface, port; proxy_url);
JSServe.HTTPServer.start(server)
JSServe.route!(server, "/" => nav);
JSServe.route!(server, "/1" => landing);
JSServe.route!(server, "/2" => landing2);

##

wait(server)