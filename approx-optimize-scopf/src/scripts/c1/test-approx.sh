#!/bin/sh

network_dir="../../../data/Network_1/"

# 601- 650 for larger network
# 301- 350 for testing
# 1-200 for training and testing
for scenario_id in $(seq 1 1);
do
    echo $scenario_id
    scenario=$network_dir"scenario_"$scenario_id"/"
    # cd $scenario || exit
    InFile1=$scenario'case.con'
    InFile2=$scenario'case.inl'
    InFile3=$scenario'case.raw'
    InFile4=$scenario'case.rop'
    NetworkModel="scenario_"$scenario_id
    echo $scenarios

    result_dir="ipopt_time_approx_valid.txt"
    save_time_dir1="stage_one_solve_time_approx_valid.txt"
    save_time_dir2="stage_two_solve_time_approx_valid.txt"

    cmd_one="julia --project='../../../' -e 'include(\"Approx1.jl\"); Approx1(\"${InFile1}\", \"${InFile2}\", \"${InFile3}\", \"${InFile4}\", 600, 2, \"${NetworkModel}\", \"${scenario}\", \"${save_time_dir1}\", \"${result_dir}\")'"
    echo $cmd_one
    eval $cmd_one&>$scenario"Approx1_"$scenario_id".log"

    cmd_two="julia --project='../../../' -e 'include(\"Approx2.jl\"); Approx2(\"${InFile1}\", \"${InFile2}\", \"${InFile3}\", \"${InFile4}\", \"${NetworkModel}\", \"${scenario}\", \"${save_time_dir2}\")'"
    echo $cmd_two
    eval $cmd_two&>$scenario"Approx2_"$scenario_id".log"
done