include("distributed.jl")
add_procs() #can be restored after package registration

@everywhere using Memento
@everywhere const LOGGER = Memento.getlogger(@__MODULE__)

@everywhere using Ipopt
@everywhere import JuMP
@everywhere import JuMP: @variable, @constraint, @NLconstraint, @objective, @NLobjective, @expression, @NLexpression

@everywhere import InfrastructureModels
@everywhere const _IM = InfrastructureModels

@everywhere import PowerModels; @everywhere const _PM = PowerModels
@everywhere import PowerModels: ids, ref, var, con, sol, nw_ids, nw_id_default

@everywhere using PowerModelsSecurityConstrained

include("second-stage-soft-fp-with-stage1.jl")
include("common.jl")
include("../../prob/opf.jl")

function Approx2(con_file::String, inl_file::String, raw_file::String, rop_file::String, network_model::String, output_dir::String="", save_time_dir::String="")
    sol1_dir = "sol1_test_approx.txt"
    save_time_dir = "solve_time_result/"*save_time_dir
    compute_c1_solution2(con_file, inl_file, raw_file, rop_file, 600000, 2, "network name"; output_dir=output_dir, scenario_id=network_model, sol1_file=sol1_dir, solve_time_file=save_time_dir)
end
