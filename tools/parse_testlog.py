#!/usr/bin/env python
# -*- coding: utf-8 -*-

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

import argparse
import json
import math
import sys

def show_test_result_summaries(testlog_json_path, testlog_txt_path):
    test_results = []
    with open(testlog_json_path, 'r') as f:
        line = f.readline()
        while line:
            test_results.append(json.loads(line.strip()))
            line = f.readline()

    num = len(test_results)
    index_width = int(math.log(num, 10) + 1) * 2 + 1

    test_name_width = 0
    for i in range(0, num):
        if len(test_results[i]["name"]) > test_name_width:
            test_name_width = len(test_results[i]["name"])
    test_name_width += 9

    for i in range(0, num):
        index = "{0}/{1}".format(i + 1, num)
        info = index.rjust(index_width) + " "
        info += test_results[i]["name"].ljust(test_name_width) + " "
        info += test_results[i]["result"].ljust(10) + " "
        duration = "{:.2f}".format(test_results[i]["duration"]) + "s"
        info += duration.rjust(10)

        if test_results[i]["returncode"] != 0:
            info += "   " + "exit status {0}".format(test_results[i]["returncode"])

        print(info)

    print("\n")
    with open(testlog_txt_path, 'r') as f:
        start_print = False
        line = f.readline()
        while line:
            if start_print:
                print(line.strip())
                line = f.readline()
                continue

            if line.startswith("Ok:"):
                start_print = True
                print(line.strip())

            line = f.readline()
    print("\n")

def main():
    parser = argparse.ArgumentParser(
        description='Take a testlog.json file and show test result summaries')
    parser.add_argument('testlog_json_path', help='The path to testlog.json', type=str)
    parser.add_argument('testlog_txt_path', help='The path to testlog.txt', type=str)

    args = parser.parse_args()

    show_test_result_summaries(args.testlog_json_path, args.testlog_txt_path)

if __name__ == "__main__":
	main()
