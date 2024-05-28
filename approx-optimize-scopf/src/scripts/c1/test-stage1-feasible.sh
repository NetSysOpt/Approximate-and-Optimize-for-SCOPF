#!/bin/sh

case_dir="../../../data/Network_1/"

# for scenario in "$network_dir"/*/;
# 601- 650 for larger network
# 301- 350 for testing
# 1-200 for training and testing
for scenario_id in $(seq 1 1);
do
    echo $scenario_id
    julia --project='../../../' generate_stage1_feasible.jl --scenario "scenario_"$scenario_id --case_dir $case_dir
done