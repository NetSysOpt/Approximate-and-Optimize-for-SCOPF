include("distributed.jl")
add_procs() #can be restored after package registration

using LinearAlgebra
using DelimitedFiles
using ArgParse

using Memento
const LOGGER = Memento.getlogger(@__MODULE__)

using Ipopt
import JuMP
import JuMP: @variable, @constraint, @NLconstraint, @objective, @NLobjective, @expression, @NLexpression

import InfrastructureModels
const _IM = InfrastructureModels

import PowerModels; const _PM = PowerModels
import PowerModels: ids, ref, var, con, sol, nw_ids, nw_id_default

using PowerModelsSecurityConstrained

include("common.jl")
include("../../prob/opf.jl")
include("approx_stage_1.jl")


function Approx1(InFile1::String, InFile2::String, InFile3::String, InFile4::String, TimeLimitInSeconds::Int64, ScoringMethod::Int64, NetworkModel::String, output_dir::String, save_time_dir::String, result_dir::String)
    println("running Approx1")
    println("  $(InFile1)")
    println("  $(InFile2)")
    println("  $(InFile3)")
    println("  $(InFile4)")
    println("  $(TimeLimitInSeconds)")
    println("  $(ScoringMethod)")
    println("  $(NetworkModel)")

    approx_solution1(InFile1, InFile2, InFile3, InFile4, NetworkModel; output_dir=output_dir, save_time_dir=save_time_dir, result_dir=result_dir)
end