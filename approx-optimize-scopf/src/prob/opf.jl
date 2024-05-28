using JuMP
using LinearAlgebra
using DelimitedFiles

"""
An OPF formulation conforming to the ARPA-e GOC Challenge 1 specification.
Power balance are strictly enforced and the branch flow violations are
penalized based on a conservative linear approximation of the formulation's
flow violation penalty specification.
"""
function run_c1_opf_cheap(file, model_constructor, solver; kwargs...)
    return _PM.run_model(file, model_constructor, solver, build_c1_opf_cheap; ref_extensions=[ref_c1!], kwargs...)
end


function build_c1_opf_cheap(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    _PM.variable_gen_power(pm)
    _PM.variable_branch_power(pm, bounded=false)

    variable_c1_branch_power_slack(pm)
    variable_c1_shunt_admittance_imaginary(pm)

    _PM.constraint_model_voltage(pm)

    for i in ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_c1_power_balance_shunt_dispatch(pm, i)
    end

    for (i,branch) in ref(pm, :branch)
        constraint_goc_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)

        _PM.constraint_voltage_angle_difference(pm, i)

        constraint_c1_thermal_limit_from_soft(pm, i)
        constraint_c1_thermal_limit_to_soft(pm, i)
    end

    ##### Setup Objective #####
    _PM.objective_variable_pg_cost(pm)
    # explicit network id needed because of conductor-less
    pg_cost = var(pm, :pg_cost)
    sm_slack = var(pm, :sm_slack)

    @objective(pm.model, Min,
        sum( pg_cost[i] for (i,gen) in ref(pm, :gen) ) +
        sum( 5e5*sm_slack[i] for (i,branch) in ref(pm, :branch_sm_active) )
    )
end


"""
A variant of `run_opf_cheap` model, specialized for solving very large
AC Power Flow models in rectangular coordinates for faster derivative
computations.  Support sparse collections of flow constrains for
increased performance.
"""
function run_c1_opf_cheap_lazy_acr(file, solver; kwargs...)
    return _PM.run_model(file, _PM.ACRPowerModel, solver, build_c1_opf_cheap_lazy_acr; ref_extensions=[ref_c1!], kwargs...)
end

""
function build_c1_opf_cheap_lazy_acr(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm, bounded=false)
    _PM.variable_gen_power(pm)

    variable_c1_branch_power_slack(pm)
    variable_c1_shunt_admittance_imaginary(pm)

    variable_c1_bus_voltage_magnitude_delta(pm)
    variable_c1_gen_power_real_delta(pm)

    vvm = var(pm)[:vvm] = @variable(pm.model,
        [i in ids(pm, :bus)], base_name="vvm",
        lower_bound = ref(pm, :bus, i, "vmin")^2,
        upper_bound = ref(pm, :bus, i, "vmax")^2,
        start = 1.0
    )


    _PM.constraint_model_voltage(pm)

    for i in ids(pm, :branch)
        expression_c1_branch_power_ohms_yt_from(pm, i)
        _PM.expression_branch_power_ohms_yt_to(pm, i)
    end


    vr = var(pm, :vr)
    vi = var(pm, :vi)
    for (i,bus) in ref(pm, :bus)
        vm_midpoint = (bus["vmax"] + bus["vmin"])/2.0
        vm_target = min(vm_midpoint + 0.04, bus["vmax"])
        #vm_target = bus["vm"]

        @constraint(pm.model, vr[i]^2 + vi[i]^2 == vvm[i])
        @constraint(pm.model, vvm[i] == vm_target^2 + var(pm, :vvm_delta, i))
    end

    for i in ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end
    #Memento.info(_LOGGER, "misc constraints time: $(time() - start_time)")


    start_time = time()
    for (i,branch) in ref(pm, :branch)
        if haskey(branch, "rate_a")
            f_bus_id = branch["f_bus"]
            t_bus_id = branch["t_bus"]
            f_idx = (i, f_bus_id, t_bus_id)
            t_idx = (i, t_bus_id, f_bus_id)

            p_fr = @variable(pm.model, base_name="p_fr", start = 0.0)
            q_fr = @variable(pm.model, base_name="q_fr", start = 0.0)
            p_to = @variable(pm.model, base_name="p_to", start = 0.0)
            q_to = @variable(pm.model, base_name="q_to", start = 0.0)

            @constraint(pm.model, var(pm, :p, f_idx) == p_fr)
            @constraint(pm.model, var(pm, :q, f_idx) == q_fr)
            @constraint(pm.model, var(pm, :p, t_idx) == p_to)
            @constraint(pm.model, var(pm, :q, t_idx) == q_to)

            rating = branch["rate_a"]
            sm_slack = var(pm, :sm_slack, i)
            JuMP.@constraint(pm.model, p_fr^2 + q_fr^2 <= (rating + sm_slack)^2)
            JuMP.@constraint(pm.model, p_to^2 + q_to^2 <= (rating + sm_slack)^2)
        end
    end
    #Memento.info(_LOGGER, "flow expr time: $(time() - start_time)")


    start_time = time()
    for (i,gen) in ref(pm, :gen)
        constraint_c1_gen_power_real_deviation(pm, i)
    end
    #Memento.info(_LOGGER, "gen expr time: $(time() - start_time)")


    p = var(pm, :p)
    q = var(pm, :q)
    pg = var(pm, :pg)
    qg = var(pm, :qg)
    bs = var(pm, :bs)
    for (i,bus) in ref(pm, :bus)
        #_PM.constraint_power_balance(pm, i)

        bus_arcs = ref(pm, :bus_arcs, i)
        bus_gens = ref(pm, :bus_gens, i)
        bus_loads = ref(pm, :bus_loads, i)
        bus_shunts_const = ref(pm, :bus_shunts_const, i)
        bus_shunts_var = ref(pm, :bus_shunts_var, i)

        bus_pd = Dict(k => ref(pm, :load, k, "pd") for k in bus_loads)
        bus_qd = Dict(k => ref(pm, :load, k, "qd") for k in bus_loads)

        bus_gs_const = Dict(k => ref(pm, :shunt, k, "gs") for k in bus_shunts_const)
        bus_bs_const = Dict(k => ref(pm, :shunt, k, "bs") for k in bus_shunts_const)

        @constraint(pm.model, 0 == - sum(p[a] for a in bus_arcs) + sum(pg[g] for g in bus_gens) - sum(pd for pd in values(bus_pd)) - sum(gs for gs in values(bus_gs_const))*vvm[i])
        @constraint(pm.model, 0 == - sum(q[a] for a in bus_arcs) + sum(qg[g] for g in bus_gens) - sum(qd for qd in values(bus_qd)) + sum(bs for bs in values(bus_bs_const))*vvm[i] + sum(bs[s]*vvm[i] for s in bus_shunts_var))
    end
    #Memento.info(_LOGGER, "power balance constraint time: $(time() - start_time)")

    vvm_delta = var(pm, :vvm_delta)
    sm_slack = var(pm, :sm_slack)
    pg_delta = var(pm, :pg_delta)

    @objective(pm.model, Min,
        sum( 1e7*vvm_delta[i]^2 for (i,bus) in ref(pm, :bus)) +
        sum( 5e5*sm_slack[i] for (i,branch) in ref(pm, :branch_sm_active)) +
        sum( 1e5*pg_delta[i]^2 for (i,gen) in ref(pm, :gen))
    )
end





"""
read the approximation model 
"""
function gelu(x)
    return 0.5 * x * (1.0 + tanh(0.7978845608028654 * (x + 0.044715 * x^3)))
end

function softplus(x; beta=1, threshold=20)
    if x > threshold
        return x
    else
        return log(1 + exp(beta*x))/beta
    end
end

mutable struct ApproxModel
    weights::Vector{Matrix{Float32}}
    biases::Vector{Vector{Float32}}
end

function create_model(hidden_list::Vector{Int})
    weights = Vector{Matrix{Float32}}(undef, length(hidden_list)+1)
    biases = Vector{Vector{Float32}}(undef, length(hidden_list)+1)
    return ApproxModel(weights, biases)
end

# create a load_weights! function for the model that can take the network architecture as a list 
function load_weights!(model::ApproxModel, path::String, input_dim, output_dim, hidden_list::Vector{Int})
    for i in 1:length(hidden_list)
        if i == 1
            model.weights[i] = reshape(readdlm(joinpath(path, "linear$(i-1)_weight.txt"), '\n', Float32)[:], input_dim, hidden_list[i])'
        else
            model.weights[i] = reshape(readdlm(joinpath(path, "linear$(i-1)_weight.txt"), '\n', Float32)[:], hidden_list[i-1], hidden_list[i])'
        end
        model.biases[i] = readdlm(joinpath(path, "linear$(i-1)_bias.txt"), '\n', Float32)[:]
    end

    if length(hidden_list) == 0
        model.weights[end] = reshape(readdlm(joinpath(path, "linear$(length(hidden_list))_weight.txt"), '\n', Float32)[:], input_dim, output_dim)'
    else
        model.weights[end] = reshape(readdlm(joinpath(path, "linear$(length(hidden_list))_weight.txt"), '\n', Float32)[:], hidden_list[end], output_dim)'
    end
    model.biases[end] = readdlm(joinpath(path, "linear$(length(hidden_list))_bias.txt"), '\n', Float32)[:]
    println("loaded the model from: ", path)
end

function create_function(model::ApproxModel, x_fixed, n_fixed)
    w1 = model.weights[1][:, 1:n_fixed]
    w2 = model.weights[1][:, n_fixed+1:end]
    fixed_weight = w1 * x_fixed

    function forward(x::T...) where {T<:Real}
        x = collect(x)
        if length(model.weights) <= 1
            return exp((fixed_weight .+ w2 * x .+ model.biases[1])[1])
        end
        x = gelu.(fixed_weight .+ w2 * x .+ model.biases[1])

        for i in 2:length(model.weights)-1
            x = gelu.(model.weights[i] * x .+ model.biases[i])
        end

        y = exp((model.weights[end] * x .+ model.biases[end])[1])
        # println()
        return y
    end
    return forward
end


"""
modified version of `run_c1_opf_cheap`, adding a approximiation of the second stage penalty into the objective function
"""
function run_c1_opf_cheap_surrogate(file, model_constructor, solver; kwargs...)
    return _PM.run_model(file, model_constructor, solver, build_c1_opf_surrogate; ref_extensions=[ref_c1!], kwargs...)
end


function build_c1_opf_surrogate(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    _PM.variable_gen_power(pm)
    _PM.variable_branch_power(pm, bounded=false)

    variable_c1_branch_power_slack(pm)
    variable_c1_shunt_admittance_imaginary(pm) ## bs, wbs

    _PM.constraint_model_voltage(pm)

    for i in ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_c1_power_balance_shunt_dispatch(pm, i)
    end

    for (i,branch) in ref(pm, :branch)
        constraint_goc_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)

        _PM.constraint_voltage_angle_difference(pm, i)

        constraint_c1_thermal_limit_from_soft(pm, i)
        constraint_c1_thermal_limit_to_soft(pm, i)
    end

    ## the load: fixed part
    nw = 0
    loads = ref(pm, nw, :load)
    idx = [i[1] for i in sort(collect(loads), by=x->x[2]["load_bus"])]
    pl = [loads[i]["pd"] for i in idx]
    ql = [loads[i]["qd"] for i in idx]
    x_fixed = [pl; ql]

    ## the variables
    pg = var(pm, :pg)
    qg = var(pm, :qg)
    vm = var(pm, :vm)
    va = var(pm, :va)

    gen = ref(pm, :gen)
    gen_idx = [i[1] for i in sort(collect(gen), by=x->x[2]["gen_bus"])]
    pg = [pg[i] for i in gen_idx]
    qg = [qg[i] for i in gen_idx]
    vm = [vm[i] for i in sort([i for i in ids(pm, :bus)])]
    va = [va[i] for i in sort([i for i in ids(pm, :bus)])]

    x = [vm; va; pg; qg]
    # x = [pg; qg]
    n = length(x)
    m = n + length(x_fixed)

    println("input length: ", m)
    println("load length: ", length(x_fixed))

    # create the model, load the weights
    hiddens = [16, 64]
    # hiddens = Vector{Int}()

    weights_dir = "path_to_weights"
    model_julia = create_model(hiddens)
    load_weights!(model_julia, weights_dir, m, 1, hiddens)
    myFunction = create_function(model_julia, x_fixed, length(x_fixed))

    # register the function to the jump model, and let the jump to calculate the gradient and hessian
    register(pm.model, :myFunction, n, myFunction, autodiff=true)

    ##### Setup Objective #####
    _PM.objective_variable_pg_cost(pm)
    # explicit network id needed because of conductor-less
    pg_cost = var(pm, :pg_cost)
    sm_slack = var(pm, :sm_slack)

    @NLobjective(pm.model, Min,
        myFunction(x...) + 
        sum( pg_cost[i] for (i,gen) in ref(pm, :gen) ) +
        sum( 5e5*sm_slack[i] for (i,branch) in ref(pm, :branch_sm_active) )
    )
end

##################################### opf for generating feasible first stage solution ##############33
"""
Modified from `run_c1_opf_cheap_target_acp`. 
If a bus is marked as fixed, then the voltage magnitude of that bus is fixed to the value of `vm_start` 
with a slack variable `vvm_delta` added to the objective function. 
Want to find the nearest solution to the `vm_start` value, by minimizing the slack variable `vvm_delta`.
"""
function run_c1_opf_cheap_fix_acp(file, solver; kwargs...)
    return _PM.run_model(file, _PM.ACPPowerModel, solver, build_c1_opf_cheap_fix_acp; ref_extensions=[ref_c1!], kwargs...)
end

""
function build_c1_opf_cheap_fix_acp(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    _PM.variable_gen_power(pm)
    _PM.variable_branch_power(pm, bounded=false)

    variable_c1_branch_power_slack(pm)
    variable_c1_shunt_admittance_imaginary(pm)

    variable_c1_bus_voltage_magnitude_delta(pm)
    variable_c1_gen_power_real_delta(pm)

    _PM.constraint_model_voltage(pm)

    vm = var(pm, :vm)
    for (i,bus) in ref(pm, :bus)
        if haskey(bus, "vm_fix")
            vm_target = bus["vm_start"]
            @constraint(pm.model, vm[i] == vm_target + var(pm, :vvm_delta, i))
        end
    end

    for i in ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for (i,gen) in ref(pm, :gen)
        if haskey(gen, "gen_fix")
            constraint_c1_gen_power_real_deviation(pm, i)
        end
    end

    for i in ids(pm, :bus)
        constraint_c1_power_balance_shunt_dispatch(pm, i)
    end

    for (i,branch) in ref(pm, :branch)
        constraint_goc_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)

        _PM.constraint_voltage_angle_difference(pm, i)

        _PM.constraint_thermal_limit_from(pm, i)
        _PM.constraint_thermal_limit_to(pm, i)
    end


    vvm_delta = var(pm, :vvm_delta)
    sm_slack = var(pm, :sm_slack)
    pg_delta = var(pm, :pg_delta)

    @objective(pm.model, Min,
        sum( 1e8*vvm_delta[i]^2 for (i,bus) in ref(pm, :bus)) +
        sum( 5e5*sm_slack[i] for (i,branch) in ref(pm, :branch)) +
        sum( 1e5*pg_delta[i]^2 for (i,gen) in ref(pm, :gen))
    )
end
