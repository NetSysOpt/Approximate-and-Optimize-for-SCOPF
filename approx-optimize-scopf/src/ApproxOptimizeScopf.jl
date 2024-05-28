module ApproxOptimizeScopf

using Distributed
using SparseArrays
import Statistics: mean

using Memento
using JSON

import JuMP
import JuMP: @variable, @constraint, @NLconstraint, @objective, @NLobjective, @expression, @NLexpression

import InfrastructureModels
const _IM = InfrastructureModels

import PowerModels; const _PM = PowerModels
import PowerModels: ids, ref, var, con, sol, nw_ids, nw_id_default

using PowerModelsSecurityConstrained

const _LOGGER = Memento.getlogger(@__MODULE__)

function __init__()
   Memento.register(_LOGGER)
   _LOGGER.name = "AOS" # note must come after register, see discussion in issue #17
end


"Suppresses information and warning messages output by PMSC, for fine grained control use the Memento package"
function silence()
    Memento.info(_LOGGER, "Suppressing information and warning messages for the rest of this session.  Use the Memento package for more fine-grained control of logging.")
    Memento.setlevel!(Memento.getlogger(InfrastructureModels), "error")
    Memento.setlevel!(Memento.getlogger(PowerModels), "error")
    Memento.setlevel!(Memento.getlogger(ApproxOptimizeScopf), "error")
end

end