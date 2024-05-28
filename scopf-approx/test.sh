#!/bin/sh

############################ single case ############################
case_dir='./examples/case2/'
raw=$case_dir'case.raw'
rop=$case_dir'case.rop'
con=$case_dir'case.con'
inl=$case_dir'case.inl'
sol1=$case_dir'sol1.txt'
sol2=$case_dir'sol2.txt'
summary=$case_dir'summary.csv'
detail=$case_dir'detail_approx.csv'

# run it
python test.py "$raw" "$rop" "$con" "$inl" "$sol1" "$sol2" "$summary" "$detail"

###########################################################################
#for idx in $(seq 601 650);
#do
#  echo $idx
#  case_dir='./data/Network_1/scenario_'
#  case_dir=$case_dir$idx"/"
#  raw=$case_dir'case.raw'
#  rop=$case_dir'case.rop'
#  con=$case_dir'case.con'
#  inl=$case_dir'case.inl'
#  sol1=$case_dir'sol1_test_approx.txt'
#  sol2=$case_dir'sol2/sol2_approx.txt'
#  summary=$case_dir'summary.csv'
#  detail=$case_dir'detail_approx_no_reg.csv'
##  sol1=$case_dir'solution1.txt'
## #  sol2=$case_dir'sol2/sol2.txt'
##  sol2=$case_dir'solution2.txt'
##  summary=$case_dir'summary.csv'
##  detail=$case_dir'detail.csv'
##   sol1=$case_dir'sol1/sol1_2_5.txt'
##   sol2=$case_dir'sol2/sol2_2_5.txt'
##   summary=$case_dir'summary.csv'
##   detail=$case_dir'detail/detail_2_5.csv'
#
#  python test.py "$raw" "$rop" "$con" "$inl" "$sol1" "$sol2" "$summary" "$detail"
#done

############################## evaluate all scenarios for a given network ################################
#network_dir='./data/Network_1'
#for scenario in "$network_dir"/*/;
#
#do
#    echo $scenario
#    raw=$scenario'case.raw'
#    rop=$scenario'case.rop'
#    con=$scenario'case.con'
#    inl=$scenario'case.inl'
#
#    sol1=$scenario'solution1.txt'
#    sol2=$scenario'sol2/sol2.txt'
#    summary=$scenario'summary.csv'
#    detail=$scenario'detail/detail.csv'
##    if [ -f "$detail" ]; then
##      continue
##    fi
##    echo $scenario
#    python test.py "$raw" "$rop" "$con" "$inl" "$sol1" "$sol2" "$summary" "$detail"
#done




############################## create sol1, sol2 folders and move all sol1_* files to sol1 folder ###########
#network_dir='./data/Network_1/'
#cd $network_dir
#for dir in */;
#do
#  cd $network_dir$dir
#  # if folder sol1 does not exists
#  if [ ! -d "sol1" ]; then
#    mkdir sol1
#  fi
#  if [ ! -d "sol2" ]; then
#    mkdir sol2
#  fi
#
#  if [ ! -d "detail" ]; then
#    mkdir detail
#  fi
#  if [ ! -d "summary" ]; then
#    mkdir summary
#  fi
#
#  if ls sol1_* 1> /dev/null 2>&1; then
#    mv sol1_* sol1/
#  fi
#done


############################# evaluate all sol2 and sol1 and generate detail.csv files in the detail folder ###########
# network_dir='/data/Network_1/'
# evaluation_dir=$(pwd)
#
# cd $network_dir
# # for scenario in */;
# for s in $(seq 1 10);
#
# do
#  ## for test: if scenario is not "scenario_9" continue
# #  if [ $scenario != "scenario_501/" ]; then
# #    continue
# #  fi
#
# scenario="scenario_"$s"/"
#
#  echo $scenario
#  cd $network_dir$scenario
#  if [ ! -d "detail" ]; then
#    mkdir detail
#  fi
#  if [ ! -d "summary" ]; then
#    mkdir summary
#  fi
#  raw=$network_dir$scenario'case.raw'
#  rop=$network_dir$scenario'case.rop'
#  con=$network_dir$scenario'case.con'
#  inl=$network_dir$scenario'case.inl'
#  # for all files in sol1 folder
#  for file1 in sol1/*;
#  # get the last part of the file name
#  do
# #    echo $file1
#    # get the last part of the file name
#    file1_name=$(basename -- $file1)
# #    echo $file1_name
#    # get the first part of the file name
#    file1_name=${file1_name%.*}
# #    echo $file1_name
#    # get the part of file name without sol1_
#    code=${file1_name#*_}
#    echo $code
#
#    # get the file name of sol2
#    file2="sol2/sol2_$code.txt"
# #    echo $file2
#    # get the file name of detail
#    detail="detail/detail_$code.csv"
# #    echo $detail
#    # get the file name of summary
#    summary="summary/summary_$code.csv"
# #    echo $summary
#    # run the approx_model_test.py
#
#    if [ ! -f "$detail" ]; then
# #      continue
#      python $evaluation_dir"/test.py" "$raw" "$rop" "$con" "$inl" "$file1" "$file2" "$summary" "$detail"
#    fi
#
# #    python $evaluation_dir"/test.py" "$raw" "$rop" "$con" "$inl" "$file1" "$file2" "$summary" "$detail"
#  done
# done
