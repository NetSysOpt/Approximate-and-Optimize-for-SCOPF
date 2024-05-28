import argparse

import pandas as pd
import os

network_dir = './data/Network_1/'
EVALUATION_RESULT_DIR = "./result/"
PMSC_DIR = "../approx-optimize-scopf/src/scripts/c1/solve_time_result/"


def update_df_pen(df, scenario):
    data = {"scenario": scenario}
    detail_dir = os.path.join(network_dir, scenario, "detail_approx_no_reg.csv")
    detail_df = pd.read_csv(detail_dir)
    obj = detail_df['obj'].values
    stage2 = {"stage1_cost": detail_df["cost"][0], "stage1_pen": detail_df["pen"][0], "stage2_pen": obj[-1] - obj[0],
              "objective": obj[-1]}
    data.update(stage2)
    if df is None or len(df) == 0:
        df = pd.DataFrame(data, index=[0])
    else:
        df = pd.concat([df, pd.DataFrame(data, index=[0])], ignore_index=True)

    return df


def main(args):
    result_df = None
    print("reading results...")
    for s in range(args.start_idx, args.end_idx + 1):
        result_df = update_df_pen(result_df, "scenario_" + str(s))

    ## read the solve_time data
    print("reading solve time...")
    if len(args.solve_time_file_name) > 0: 
        solve_time_df = pd.read_csv(PMSC_DIR + args.solve_time_file_name)
        if "objective" in solve_time_df.columns:
            solve_time_df = solve_time_df.drop(columns=["objective"])

        ## merge the two dataframes
        result_df = pd.merge(result_df, solve_time_df, on="scenario")

    result_df.to_csv(EVALUATION_RESULT_DIR + args.result_file_name, index=False)
    print("done!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Generate results for scenarios with objective, penalty and solve time')
    parser.add_argument('--start_idx', type=int, default=601)
    parser.add_argument('--end_idx', type=int, default=650)
    parser.add_argument('--solve_time_file_name', type=str, default='stage_one_solve_time_approx_no_regularization_larger.txt')
    parser.add_argument('--result_file_name', type=str, default='result_approx_no_regularization_larger.csv')

    args = parser.parse_args()

    main(args)