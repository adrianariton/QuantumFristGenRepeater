retina_scale = 2
config = Dict(
    :resolution => (retina_scale*1400, retina_scale*700), # used for the main figures
    :smallresolution => (280, 160),                       # used for the menufigures
    :colorscheme => ["rgb(11, 42, 64)", "white", "#1f77b4", "white"]
    # :colorscheme => ["rgb(242, 242, 247)", "black", "#000529", "white"]
    # :colorscheme => ["rgb(242, 242, 247)", "black", "rgb(242, 242, 247)", "black"]
)
menufigs_style = """
        display:flex;
        flex-direction: row;
        justify-content: space-around;
        background-color: $(config[:colorscheme][1]);
        padding-top: 20px;
        width: $(config[:resolution][1]/retina_scale)px;
    """


style = DOM.style("""
    body {
        font-family: Arial;
    }
    .console_line:hover{
        background-color: rgba(38, 39, 41, 0.6);
        cursor: pointer;
    }
    .log_wrapper{
        max-height: 65vh !important; max-width: 90% !important; color: white; 
        display: flex;
        flex-direction: column-reverse;
        border-left: 2px solid rgb(38, 39, 41);
        border-bottom: 2px solid rgb(38, 39, 41);
        min-height: 40px !important;
        background-color: rgb(11, 42, 64);
        overflow: auto;
    }
    .backbutton{
        color: $(config[:colorscheme][4]) !important;
        background-color: white;
        padding: 10px;
        height: min-content;
    }

    .backbutton:hover{
        color: $(config[:colorscheme][4]) !important;
        opacity: 0.8;
    }

    .backbutton a{
        font-weight: bold;
    }
    .nostyle{
        border: none !important;
        padding: 0 0 0 0 !important;
        margin: 0 0 0 0 !important;
        background: transparent !important;
    }
    .hide{
        display: none;
    }
    .active {
        background-color: rgba(38, 39, 41, 0.8);
    }
    .infodiv{
        color: white;
        background-color: $(config[:colorscheme][3]);
        padding: 10px;
    }
""")