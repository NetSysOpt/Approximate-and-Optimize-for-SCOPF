import pandas as pd
import numpy as np
import os
import evaluation
import data
import math

network_dir = './data/Network_1/'
eval_dir = '/ScopfApprox/data/'


BASE = 100


# the power need to be rescaled by the BASE the angle need to be rescaled by the pi/180. It is of radian when doing
# calculation, but it is of degree when reading from the raw file


def get_load_data(scenario):
    raw_name = os.path.join(network_dir, scenario, 'case.raw')
    p = data.Data()
    p.raw.read(raw_name)
    loads = sorted(p.raw.loads.values(), key=lambda x: x.i)
    dic = {"pl" + str(l.i): l.pl / BASE for l in loads}
    q_dic = {"ql" + str(l.i): l.ql / BASE for l in loads}
    dic.update(q_dic)
    return dic


def get_stage2_pen(scenario, code):
    if code:
        code = "_" + code
    else:
        code = ""
    detail_dir = os.path.join(network_dir, scenario, "detail", "detail" + code + ".csv")
    df = pd.read_csv(detail_dir)
    print(len(df))
    obj = df['obj'].values
    return {"stage2_pen": obj[-1] - obj[0]}


def get_stage1_sol(scenario, code, sol1_dir="sol1/sol1_"):
    sol1_dir = os.path.join(network_dir, scenario, sol1_dir + code + ".txt")
    raw_name = os.path.join(network_dir, scenario, 'case.raw')
    p = data.Data()
    p.raw.read(raw_name)
    num_bus = len(p.raw.buses)
    num_gen = len(p.raw.generators)
    s1 = evaluation.Solution1()
    s1.read(sol1_dir, num_bus, num_gen)
    # sort the bus_df by the value of column "i"
    s1.bus_df = s1.bus_df.sort_values(by="i", ascending=True).reset_index(drop=True)
    s1.gen_df = s1.gen_df.sort_values(by="i", ascending=True).reset_index(drop=True)
    dic = {"vm" + str(int(s1.bus_df.iloc[i]["i"])): s1.bus_df.iloc[i]["vm"] for i in range(len(s1.bus_df))}
    va_dic = {"va" + str(int(s1.bus_df.iloc[i]["i"])): s1.bus_df.iloc[i]["va"] * (math.pi / 180.0) for i in
              range(len(s1.bus_df))}
    pg_dic = {"pg" + str(int(s1.gen_df.iloc[i]["i"])): s1.gen_df.iloc[i]["pg"] / BASE for i in range(len(s1.gen_df))}
    qg_dic = {"qg" + str(int(s1.gen_df.iloc[i]["i"])): s1.gen_df.iloc[i]["qg"] / BASE for i in range(len(s1.gen_df))}
    dic.update(va_dic)
    dic.update(pg_dic)
    dic.update(qg_dic)
    return dic


def update_df(df, scenario, code):
    load = get_load_data(scenario)
    stage1 = get_stage1_sol(scenario, code)
    stage2 = get_stage2_pen(scenario, code)
    load.update(stage1)
    load.update(stage2)
    if df is None or len(df) == 0:
        df = pd.DataFrame(load, index=[0])
    else:
        # df = pd.concat(df, load, ignore_index=True)
        df = pd.concat([df, pd.DataFrame(load, index=[0])], ignore_index=True)

    return df

def get_stage2_penv2(scenario, code):
    if code:
        code = "_" + code
    else:
        code = ""
    detail_dir = os.path.join(network_dir, scenario, "detail", "detail" + code + ".csv")
    df = pd.read_csv(detail_dir)
    print(len(df))
    obj = df['obj'].values
    return {"stage1_obj": obj[0], "stage2_pen": obj[-1] - obj[0]}

def update_df_pen(df, scenario, code=""):
    data = {"scenario": scenario}
    stage2 = get_stage2_penv2(scenario, code)
    data.update(stage2)
    if df is None or len(df) == 0:
        df = pd.DataFrame(data, index=[0])
    else:
        df = pd.concat([df, pd.DataFrame(data, index=[0])], ignore_index=True)

    return df

###################### genearte data ############################
df = None
n_all = 200
n_train = 120
n_val = 50
n_test = 30
for s in range(1, 200):
# for s in range(10, 10):
    for i in range(1, 11):
        for j in range(1, 6):
            code = str(i) + "_" + str(j)
            df = update_df(df, "scenario_" + str(s), code)

df.to_csv(eval_dir+"stage2_pen.csv", index=False)

# write the inactive columns to a file
cols = df.columns.tolist()
inactive_cols = []
for c in cols:
    if np.sum(df[c].values) == 0:
        inactive_cols.append(c)
with open(eval_dir+"inactive_cols.txt", "w") as f:
    for c in inactive_cols:
        f.write(c + "\n")
df.drop(columns=inactive_cols, inplace=True)
df.to_csv(eval_dir+"stage2_pen_active.csv", index=False)
df_train = df.iloc[:n_train*50]
df_train.to_csv(eval_dir+"stage2_pen_train.csv", index=False)
df_val = df.iloc[n_train*50: (n_train+n_val)*50]
df_val.to_csv(eval_dir+"stage2_pen_val.csv", index=False)
df_test = df.iloc[(n_train+n_val)*50:]
df_test.to_csv(eval_dir+"stage2_pen_test.csv", index=False)

###################### get only penalty ########################
# df2 = None
# for s in range(501, 503):
#     df2 = update_df_pen(df, "scenario_" + str(s))
# df2.to_csv("/ScopfApprox/data/stage2_tmp.csv", index=False)