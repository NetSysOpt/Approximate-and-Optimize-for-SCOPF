
function write_c1_scopf_summary(scenario_id, network, objective; branch_flow_cuts=0, objective_lb=-Inf, load_time=-1.0, solve_time=-1.0, filter_time=-1.0, total_time=load_time+solve_time+filter_time)
    println("")

    data = [
        "----",
        "scenario id",
        "num bus",
        "num branch",
        "num gen",
        "num load",
        "num shunt",
        "num gen cont",
        "num branch cont",
        "active gen cont",
        "active branch cont",
        "branch flow cuts",
        "objective ub",
        "objective lb",
        "load time (sec.)",
        "solve time (sec.)",
        "filter time (sec.)",
        "total time (sec.)",
    ]
    println(join(data, ", "))

    data = [
        "DATA",
        scenario_id,
        length(network["bus"]),
        length(network["branch"]),
        length(network["gen"]),
        length(network["load"]),
        length(network["shunt"]),
        length(network["gen_contingencies"]),
        length(network["branch_contingencies"]),
        length(network["gen_contingencies_active"]),
        length(network["branch_contingencies_active"]),
        branch_flow_cuts,
        objective,
        objective_lb,
        load_time,
        solve_time,
        filter_time,
        total_time,
    ]
    println(join(data, ", "))

end


function write_c1_power_balance_summary(scenario_id, p_delta_abs_max, q_delta_abs_max, p_delta_abs_mean, q_delta_abs_mean)
    println("")

    data = [
        "----",
        "scenario id",
        "p_delta abs max",
        "q_delta abs max",
        "p_delta abs mean",
        "q_delta abs mean",
    ]
    println(join(data, ", "))

    data = [
        "DATA_PB",
        scenario_id,
        p_delta_abs_max,
        q_delta_abs_max,
        p_delta_abs_mean,
        q_delta_abs_mean,
    ]
    println(join(data, ", "))

end

function write_solve_time(filename, scenario_id, objective; load_time=-1.0, solve_time=-1.0, filter_time=-1.0, total_time=load_time+solve_time+filter_time)
    data = [
        scenario_id,
        objective,
        load_time,
        solve_time,
        filter_time,
        total_time,
    ]
    if !isfile(filename)
        cols = [
            "scenario",
            "objective",
            "load_time",
            "solve_time",
            "filter_time",
            "total_time"
        ]
        open(filename, "a") do io
            println(io, join(cols, ","))
        end
    end

    open(filename, "a") do io
        println(io, join(data, ","))
    end
end

function write_solve_time(filename, result, scenario)
    if !isfile(filename)
        cols = [
            "scenario",
            "ipopt_obj",
            "ipopt_time",
            "termination_status"
        ]
        open(filename, "a") do io
            println(io, join(cols, ","))
        end
    end

    data = [
        scenario,
        result["objective"],
        result["solve_time"],
        result["termination_status"]
    ]
    open(filename, "a") do io
        println(io, join(data, ","))
    end
end

function write_solve_time_stage2(filename, time, scenario)
    if !isfile(filename)
        cols = [
            "scenario",
            "second_stage_runtime"
        ]
        open(filename, "a") do io
            println(io, join(cols, ","))
        end
    end

    data = [
        scenario,
        time
    ]
    open(filename, "a") do io
        println(io, join(data, ","))
    end
end