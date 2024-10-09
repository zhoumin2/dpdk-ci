# -*- coding: utf-8 -*-
#!/bin/python

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2024 Loongson

from datetime import datetime, timedelta
import argparse
import csv
import json
import os
import subprocess

def get_recheck_time(path):
    now = datetime.now()
    rc_time = now + timedelta(hours=-12)
    rt_str = rc_time.strftime("%Y-%m-%dT%H:%M:%S")

    if not os.path.exists(path):
        fp = open(path, "w")
        return rt_str

    fp = open(path)
    if fp == None:
        return rt_str

    last = fp.readline().strip()
    fp.close()

    if len(last) == 0:
        return rt_str

    tmp = datetime.strptime(last, "%Y-%m-%dT%H:%M:%S")
    if now - tmp > timedelta(hours=12):
        return rt_str

    return last

def set_recheck_time(path, rt_str):
    fp = open(path, "w")
    if fp == None:
        return

    fp.write(rt_str)
    fp.close()

def save_recheck_time(path, rechecks):
    last_ts = rechecks['last_comment_timestamp']
    if last_ts != None:
        set_recheck_time(path, last_ts.split('.')[0])

def get_retest_times(path, sid, last_ts):
    times = 1
    if last_ts != None:
        last_ts = last_ts.split('.')[0]

    if not os.path.exists(path):
        fp = open(path, "w")
        return times

    with open(path, newline='') as csvfile:
        retest_reader = csv.reader(csvfile, delimiter=' ', quotechar='|')
        for row in retest_reader:
            if row[0] == sid:
                if last_ts != None and row[1] == last_ts:
                    return -1
                times += 1

    return times

def recheck_db_insert(path, sid, last_ts):
    if last_ts == None:
        return

    last_ts = last_ts.split('.')[0]
    fp = open(path, "a")
    fp.write(str(sid) + " " + last_ts + "\n")
    fp.close()

def main():
    parser = argparse.ArgumentParser(
        description='recheck whether to rerun or not for LoongArch')
    parser.add_argument('last_file', help='The file to save last recheck time',
            type=str)
    parser.add_argument('recheck_db', help='The database of recheck status', type=str)

    args = parser.parse_args()

    directory = os.path.split(os.path.realpath(__file__))[0]
    script_path = os.path.join(directory, 'get_reruns.py')
    print("get_reruns.py: " + script_path)

    ts = get_recheck_time(args.last_file)
    print("recheck time: " + ts)
    p = subprocess.run(['/usr/bin/python3.8', script_path, '-ts', ts, '--contexts', 'loongarch-compilation',
        'loongarch-unit-testing'], capture_output=True)
    print(p.stdout)
    if len(p.stdout) == 0:
        return

    try:
        rechecks = json.loads(p.stdout)
    except:
        print("decode the results of get_reruns.py failed!")
        return

    if len(rechecks['retests'].keys()) == 0:
        save_recheck_time(args.last_file, rechecks)
        return

    last_ts = rechecks['last_comment_timestamp']
    script_path = os.path.join(directory, 'retest-series.sh')
    print("retest-series.sh: " + script_path)
    for sid in rechecks['retests'].keys():
        times = get_retest_times(args.recheck_db, sid, last_ts)
        if times == -1:
            continue
        subprocess.run(['/usr/bin/bash', script_path, '-t', str(times), sid])
        recheck_db_insert(args.recheck_db, sid, last_ts)

    save_recheck_time(args.last_file, rechecks)

if __name__ == "__main__":
    main()
