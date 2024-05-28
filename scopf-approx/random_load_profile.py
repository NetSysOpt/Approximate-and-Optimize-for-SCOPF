import argparse
import csv
import os
import random


def row_is_file_end(row):
    is_file_end = False
    if len(row) == 0:
        is_file_end = True
    if row[0][:1] in {'', 'q', 'Q'}:
        is_file_end = True
    return is_file_end


def row_is_section_end(row):
    is_section_end = False
    if row[0][:1] == '0':
        is_section_end = True
    return is_section_end


def main(file_name, case_name="case_new.raw", lb=0.9, ub=1.1):
    with open(file_name, 'r') as in_file:
        lines = in_file.readlines()
    delimiter_str = ","
    quote_str = "'"
    skip_initial_space = True
    rows = csv.reader(
        lines,
        delimiter=delimiter_str,
        quotechar=quote_str,
        skipinitialspace=skip_initial_space)
    rows = [[t.strip() for t in r] for r in rows]

    read_from_rows(rows, lines, case_name, lb, ub)


def read_from_rows(rows, lines, case_name, lb=0.9, ub=1.1):
    # keep the first three rows
    with open(case_name, 'a+') as out_file:
        for lin in lines[:3]:
            out_file.write(lin)
    row_num = 2
    # cid_rows = rows[row_num:(row_num + 3)]
    # self.case_identification.read_from_rows(rows)
    # row_num += 2
    # BUS DATA
    while True:
        row_num += 1
        row = rows[row_num]

        with open(case_name, 'a+') as out_file:
            out_file.write(lines[row_num])

        if row_is_file_end(row):
            return
        if row_is_section_end(row):
            break

    # LOAD DATA
    while True:
        row_num += 1
        row = rows[row_num]

        if row_is_file_end(row):
            with open(case_name, 'a+') as out_file:
                out_file.write(lines[row_num])
            return
        if row_is_section_end(row):
            with open(case_name, 'a+') as out_file:
                out_file.write(lines[row_num])
            break
        pl = float(row[5])
        ql = float(row[6])

        # random load profile, by a factor unifromly sampled from [0.9, 1.1]
        pl = pl * random.uniform(lb, ub)
        ql = ql * random.uniform(lb, ub)
        # pl = pl * random.uniform(0.7, 1.3)
        # ql = ql * random.uniform(0.7, 1.3)

        line = lines[row_num].split(",")
        line[5] = str(pl)
        line[6] = str(ql)
        line = ",".join(line)
        with open(case_name, 'a+') as out_file:
            out_file.write(line)

    with open(case_name, 'a+') as out_file:
        for lin in lines[row_num+1:]:
            out_file.write(lin)


if __name__ == '__main__':
    # create parser
    parser = argparse.ArgumentParser(description='Generate data for power system security constrained optimal power flow.')
    parser.add_argument('--raw_dir', type=str, default='case.raw', help='the directory of the case.raw file after modification')
    parser.add_argument('--file_name', type=str, default='case_orig.raw', help='the directory of the case.raw file')
    raw_dir = parser.parse_args().raw_dir
    file_name = parser.parse_args().file_name
    if os.path.exists(raw_dir):
        os.remove(raw_dir)
    main(file_name, raw_dir)
