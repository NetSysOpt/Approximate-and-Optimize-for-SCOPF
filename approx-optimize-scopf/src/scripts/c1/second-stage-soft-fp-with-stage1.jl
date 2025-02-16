
function compute_c1_solution2(con_file::String, inl_file::String, raw_file::String, rop_file::String, time_limit::Int, scoring_method::Int, network_model::String; output_dir::String="", scenario_id::String="none", sol1_file::String="solution1.txt", solve_time_file="second_stage_solve_time.txt")
    time_data_start = time()
    goc_data = parse_c1_files(con_file, inl_file, raw_file, rop_file, scenario_id=scenario_id)
    network = build_c1_pm_model(goc_data)
    load_time = time() - time_data_start

    ###### Prepare Solution 2 ######

    time_contingencies_start = time()

    gen_cont_total = length(network["gen_contingencies"])
    branch_cont_total = length(network["branch_contingencies"])
    cont_total = gen_cont_total + branch_cont_total

    cont_order = contingency_order(network)

    #for cont in cont_order
    #    println(cont.label)
    #end

    workers = Distributed.workers()

    process_data = []

    cont_per_proc = cont_total/length(workers)

    for p in 1:length(workers)
        cont_start = trunc(Int, ceil(1+(p-1)*cont_per_proc))
        cont_end = min(cont_total, trunc(Int,ceil(p*cont_per_proc)))
        pd = (
            pid = p,
            processes = length(workers),
            con_file = con_file,
            inl_file = inl_file,
            raw_file = raw_file,
            rop_file = rop_file,
            scenario_id = scenario_id,
            output_dir = output_dir,
            cont_range = cont_start:cont_end,
            sol1_file=sol1_file
        )
        #println(pd)
        push!(process_data, pd)
    end

    for (i,pd) in enumerate(process_data)
        info(LOGGER, "worker task $(pd.pid): $(length(pd.cont_range)) / $(pd.cont_range)")
    end

    #for (i,pd) in enumerate(process_data)
    #    println(pd.pid)
    #    for cont in cont_order[pd.cont_range]
    #        println("$(cont.label)")
    #    end
    #end

    # map the c1_solution2_solver function to the process_data array
    solution2_files = pmap(c1_solution2_solver, process_data)

    # solution2_files = []
    # for pd in process_data
    #     push!(solution2_files, c1_solution2_solver(pd))
    # end

    sort!(solution2_files)

    #println("pmap result: $(solution2_files)")

    time_contingencies = time() - time_contingencies_start
    info(LOGGER, "contingency eval time: $(time_contingencies)")

    info(LOGGER, "combine $(length(solution2_files)) solution2 files")

    # extract the characters excepts the first 4 from sol1_file
    # e.g. sol1/sol1_1_1.txt -> 1_1
    case_code = sol1_file[10:end-3]
    # if case_code is empty
    if case_code == ""
        sol2_file = "solution2.txt"
    end
        sol2_file = "sol2/sol2" * case_code * "txt"
    c1_combine_files(solution2_files, sol2_file; output_dir=output_dir)
    remove_c1_files(solution2_files)

    println("")

    data = [
        "----",
        "scenario id",
        "bus",
        "branch",
        "gen_cont",
        "branch_cont",
        "runtime (sec.)",
    ]
    println(join(data, ", "))

    data = [
        "DATA_SSS",
        goc_data.scenario,
        length(network["bus"]),
        length(network["branch"]),
        length(network["gen_contingencies"]),
        length(network["branch_contingencies"]),
        time_contingencies,
    ]
    println(join(data, ", "))

    write_c1_file_paths(goc_data.files; output_dir=output_dir, solution1_file=sol1_file, solution2_file=sol2_file)
    println("second stage: ", solve_time_file)
    write_solve_time_stage2(solve_time_file, time_contingencies, goc_data.scenario)
    
    #println("")
    #write_evaluation_summary(goc_data, network, objective_lb=-Inf, load_time=load_time, contingency_time=time_contingencies, output_dir=output_dir)
end


@everywhere function c1_solution2_solver(process_data)
    #println(process_data)
    time_data_start = time()
    _PM.silence()
    goc_data = parse_c1_files(
        process_data.con_file, process_data.inl_file, process_data.raw_file,
        process_data.rop_file, scenario_id=process_data.scenario_id)
    network = build_c1_pm_model(goc_data)

    sol = read_c1_solution1(network, output_dir=process_data.output_dir, state_file=process_data.sol1_file)
    _PM.update_data!(network, sol)
    time_data = time() - time_data_start

    for (i,bus) in network["bus"]
        if haskey(bus, "evhi")
            bus["vmax"] = bus["evhi"]
        end
        if haskey(bus, "evlo")
            bus["vmin"] = bus["evlo"]
        end
    end

    for (i,branch) in network["branch"]
        if haskey(branch, "rate_c")
            branch["rate_a"] = branch["rate_c"]
        end
    end

    contingencies = contingency_order(network)[process_data.cont_range]

    for (i,branch) in network["branch"]
        g, b = _PM.calc_branch_y(branch)
        tr, ti = _PM.calc_branch_t(branch)
        branch["g"] = g
        branch["b"] = b
        branch["tr"] = tr
        branch["ti"] = ti
    end

    bus_gens = gens_by_bus(network)

    network["delta"] = 0.0
    for (i,bus) in network["bus"]
        bus["vm_base"] = bus["vm"]
        bus["vm_start"] = bus["vm"]
        bus["va_start"] = bus["va"]
        bus["vm_fixed"] = length(bus_gens[i]) != 0
    end

    for (i,gen) in network["gen"]
        gen["pg_base"] = gen["pg"]
        gen["pg_start"] = gen["pg"]
        gen["qg_start"] = gen["qg"]
        gen["pg_fixed"] = false
        gen["qg_fixed"] = false
    end

    #nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, hessian_approximation="limited-memory", print_level=0)
    nlp_solver = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol"=>1e-6, "print_level"=>0)
    #nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6)
    #nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, hessian_approximation="limited-memory")

    #contingency_solutions = []

    pad_size = trunc(Int, ceil(log(10,process_data.processes)))
    padded_pid = lpad(string(process_data.pid), pad_size, "0")
    solution_filename = "solution2-$(padded_pid).txt"

    if length(process_data.output_dir) > 0
        solution_path = joinpath(process_data.output_dir, solution_filename)
    else
        solution_path = solution_filename
    end
    if isfile(solution_path)
        warn(LOGGER, "removing existing solution2 file $(solution_path)")
        rm(solution_path)
    end
    open(solution_path, "w") do sol_file
        # creates an empty file in the case of workers without contingencies
    end

    ################### debug, remove latter ###############
    # contingency_time_filename = "contingency_time_benchmark.txt"
    # contingency_time_filename = "contingency_time_approx.txt"
    # open(contingency_time_filename, "a") do io
    #     println(io, join(["contingency", "solve_time"], ","))
    # end

    #network_tmp = deepcopy(network)
    for cont in contingencies
        if cont.type == "gen"
            info(LOGGER, "working on: $(cont.label)")
            time_start = time()
            network_tmp = deepcopy(network)
            # info(LOGGER, "contingency $(cont.label) copy time: $(time() - time_start)")
            debug(LOGGER, "contingency copy time: $(time() - time_start)")
            network_tmp["cont_label"] = cont.label

            cont_gen = network_tmp["gen"]["$(cont.idx)"]
            cont_gen["contingency"] = true
            cont_gen["gen_status"] = 0
            pg_lost = cont_gen["pg"]

            gen_bus = network_tmp["bus"]["$(cont_gen["gen_bus"])"]
            if length(bus_gens["$(gen_bus["index"])"]) == 1
                gen_bus["vm_fixed"] = false
            end

            network_tmp["response_gens"] = network_tmp["area_gens"][gen_bus["area"]]

            time_start = time()
            ################### need to change back to pvpq! ###############
            # result = run_c1_fixpoint_pf_bqv!(network_tmp, pg_lost, nlp_solver, iteration_limit=10)
            result = run_c1_fixpoint_pf_pvpq!(network_tmp, pg_lost, nlp_solver, iteration_limit=10)
            # debug(LOGGER, "second-stage contingency solve time: $(time() - time_start)")
            ######################
            info(LOGGER, "second-stage contingency $(cont.label) solve time: $(time() - time_start)")
            # open(contingency_time_filename, "a") do io
            #     println(io, join(["$(cont.label)", "$(time() - time_start)"], ","))
            # end

            cont_sol = result["solution"]
            if !(result["termination_status"] == _PM.LOCALLY_SOLVED || result["termination_status"] == _PM.ALMOST_LOCALLY_SOLVED)
                warn(LOGGER, "$(cont.label) contingency solve status: $(result["termination_status"])")
                cont_sol = deepcopy(sol)
            end
            cont_sol["label"] = cont.label
            cont_sol["feasible"] = (result["termination_status"] == _PM.LOCALLY_SOLVED)
            cont_sol["cont_type"] = "gen"
            cont_sol["cont_comp_id"] = cont.idx

            cont_sol["gen"]["$(cont.idx)"] = Dict("pg" => 0.0, "qg" => 0.0)
            cont_sol["delta"] = 0.0

            #push!(contingency_solutions, result["solution"])
            correct_c1_contingency_solution!(network, cont_sol)
            open(solution_path, "a") do sol_file
                sol2 = write_c1_solution2_contingency(sol_file, network, cont_sol)
            end

            network_tmp["gen"]["$(cont.idx)"]["gen_status"] = 1
        elseif cont.type == "branch"
            info(LOGGER, "working on: $(cont.label)")
            time_start = time()
            network_tmp = deepcopy(network)
            #########################
            info(LOGGER, "contingency $(cont.label) copy time: $(time() - time_start)")
            # debug(LOGGER, "contingency copy time: $(time() - time_start)")
            network_tmp["cont_label"] = cont.label
            cont_branch = network_tmp["branch"]["$(cont.idx)"]
            cont_branch["br_status"] = 0

            fr_bus = network_tmp["bus"]["$(cont_branch["f_bus"])"]
            to_bus = network_tmp["bus"]["$(cont_branch["t_bus"])"]
            network_tmp["response_gens"] = Set()
            if haskey(network_tmp["area_gens"], fr_bus["area"])
                network_tmp["response_gens"] = network_tmp["area_gens"][fr_bus["area"]]
            end
            if haskey(network_tmp["area_gens"], to_bus["area"])
                network_tmp["response_gens"] = union(network_tmp["response_gens"], network_tmp["area_gens"][to_bus["area"]])
            end

            time_start = time()
            ################### need to change back to pvpq! ###############
            # result = run_c1_fixpoint_pf_bqv!(network_tmp, 0.0, nlp_solver, iteration_limit=10)
            result = run_c1_fixpoint_pf_pvpq!(network_tmp, 0.0, nlp_solver, iteration_limit=10)
            info(LOGGER, "second-stage contingency $(cont.label) solve time: $(time() - time_start)")
            # open(contingency_time_filename, "a") do io
            #     println(io, join(["$(cont.label)", "$(time() - time_start)"], ","))
            # end
            # debug(LOGGER, "second-stage contingency solve time: $(time() - time_start)")
            cont_sol = result["solution"]
            if !(result["termination_status"] == _PM.LOCALLY_SOLVED || result["termination_status"] == _PM.ALMOST_LOCALLY_SOLVED)
                warn(LOGGER, "$(cont.label) contingency solve status: $(result["termination_status"])")
                cont_sol = deepcopy(sol)
            end
            cont_sol["label"] = cont.label
            cont_sol["feasible"] = (result["termination_status"] == _PM.LOCALLY_SOLVED)
            cont_sol["cont_type"] = "branch"
            cont_sol["cont_comp_id"] = cont.idx

            cont_sol["delta"] = 0.0

            #push!(contingency_solutions, cont_sol)
            correct_c1_contingency_solution!(network, cont_sol)
            open(solution_path, "a") do sol_file
                sol2 = write_c1_solution2_contingency(sol_file, network, cont_sol)
            end

            network_tmp["branch"]["$(cont.idx)"]["br_status"] = 1
        else
            @assert("contingency type $(cont.type) not known")
        end
    end

    return solution_path
end
