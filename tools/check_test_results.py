# -*- coding: utf-8 -*-
#!/bin/python

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

import argparse
from datetime import date,datetime,timedelta
import time
import json
import os
import requests

def try_request(url, retry=3):
    i = 0
    while i < retry:
        try:
            r = requests.get(url)
            data = json.loads(r.text)
            return data
        except:
            i += 1
            time.sleep(1)

    print(r.text)
    return None

def get_patch_checks(pid):
    url = "http://patches.dpdk.org/api/patches/" + str(pid) + "/checks/"
    print(url)
    data = try_request(url)
    if data == None:
        print("Parse checks info failed for patch %s" % (str(pid)))
        return []

    return data

def get_patch_url(pid):
    return "http://dpdk.org/patch/" + str(pid)

def get_series_url(sid):
    return "http://patches.dpdk.org/project/dpdk/list/?series=" + str(sid) + "&archive=both&state=*"

class Series:
    def __init__(self, sid = -1, patches = [], c_time = 0, valid = False, message=""):
        self.sid = sid
        self.patches = patches
        self.c_time = c_time
        self.valid = valid
        self.first_id = -1
        self.last_id = -1
        self.checks = {}
        self.la_compilation = "missed"
        self.la_unit_test = "missed"
        self.has_checks = False
        self.message = message

        if len(self.patches) == 0:
            self.valid = False

        if not self.valid:
            return

        self.first_id = self.patches[0]
        self.last_id = self.patches[len(self.patches) - 1]

    def filter_la_checks(self):
        if not self.valid:
            return

        if not self.has_checks:
            ret = self.get_checks()
            if not ret:
                return

        if self.last_id in self.checks:
            for check in self.checks[self.last_id]:
                if check["context"] == "loongarch-compilation":
                    self.la_compilation = check["state"]
                elif check["context"] == "loongarch-unit-testing":
                    self.la_unit_test = check["state"]

        if self.first_id in self.checks:
            for check in self.checks[self.first_id]:
                if check["context"] == "loongarch-compilation":
                    self.la_compilation = check["state"]
                elif check["context"] == "loongarch-unit-testing":
                    self.la_unit_test = check["state"]

    def get_checks(self):
        if not self.valid:
            return False

        if self.last_id not in self.checks:
            checks = get_patch_checks(self.last_id)
            if len(checks) > 0:
                self.checks[self.last_id] = checks
                self.has_checks = True

        if self.first_id not in self.checks:
            checks = get_patch_checks(self.first_id)
            if len(checks) > 0:
                self.checks[self.first_id] = checks
                self.has_checks = True

        if not self.has_checks:
            self.valid = False
            self.message = "get series checks failed"
            return False

        return True

def get_series_ids(pre_days):
    today = date.today()
    since = today - timedelta(pre_days)
    page = 1
    series_ids = []
    URL = "http://patches.dpdk.org/api/events/?category=series-completed"

    while True:
        url = URL + "&page=" + str(page) + "&since=" + since.strftime("%Y-%m-%dT%H:%M:%S")
        print(url)
        data = try_request(url)
        if data == None:
            print("Parse series-completed response failed for url: %s" % (url))
            sys.exit(0)

        if not isinstance(data, list):
            print(data)
            break

        print(len(data))
        if len(data) == 0:
                break

        for item in data:
            if item["project"]["name"] == "DPDK":
                series_ids.append(item["payload"]["series"]["id"])
        page += 1

    return series_ids

def get_series_by_id(sid):
    url = "http://patches.dpdk.org/api/series/" + str(sid)
    print(url)
    data = try_request(url)
    if data == None:
        print("Parse series info failed for series %s" % (str(sid)))
        return Series(sid=sid, valid=False, message="get series info failed")

    c_time = time.mktime(datetime.strptime(data["date"], "%Y-%m-%dT%H:%M:%S").timetuple()) + 28800
    if time.time() - c_time < 3600:
        print("Ignore series %s which committed at %s" % (str(sid), data["date"]))
        return Series(sid=sid, c_time=c_time, valid=False, message="ignored for committed time ("+data["date"]+")")

    patches = []
    for p in data["patches"]:
        patches.append(p["id"])

    series = Series(sid=sid, patches=patches, c_time=c_time, valid=True)
    series.get_checks()
    series.filter_la_checks()

    return series

def get_series_set(series_ids):
    series_set = []
    for sid in series_ids:
        series_set.append(get_series_by_id(sid))

    return series_set

def check_test_results(pre_days, log_file):
    series_ids = []
    series_set = []
    info_invalid = ""
    info_warn_miss = ""
    info_fail_miss = ""
    info_succ_miss = ""
    info_succ_fail = ""
    info_succ_succ = ""

    series_ids = get_series_ids(pre_days)
    if len(series_ids) == 0:
        return
    print(series_ids)

    series_set = get_series_set(series_ids)
    for series in series_set:
        if not series.valid:
            info = get_series_url(series.sid) + ": " + series.message
            info_invalid += info + "\n"
            continue

        info = get_series_url(series.sid) + ": compilation is " + series.la_compilation
        info += ", unit-testing is " + series.la_unit_test

        if series.la_compilation == "warning":
            info_warn_miss += info + "\n"
        elif series.la_compilation == "fail":
            info_fail_miss += info + "\n"
        elif series.la_compilation == "success":
            if series.la_unit_test == "missed":
                info_succ_miss += info + "\n"
            elif series.la_unit_test == "fail":
                info_succ_fail += info + "\n"
            else:
                info_succ_succ += info + "\n"

    info = ""
    if info_warn_miss != "":
        info += info_warn_miss + "\n"
    if info_fail_miss != "":
        info += info_fail_miss + "\n"
    if info_succ_miss != "":
        info += info_succ_miss + "\n"
    if info_succ_fail != "":
        info += info_succ_fail + "\n"

    if info_invalid != "":
        info += info_invalid + "\n"

    if info_succ_succ != "":
        info += info_succ_succ
    print(info)

    fp = open(log_file, "w")
    if info != "":
        fp.write(info)

    fp.close()

def main():
    parser = argparse.ArgumentParser(
        description='check the test results from LoongArch for these patches'
            ' committed in the last few days')
    parser.add_argument('pre_days', help='The last few days to check', type=int)
    parser.add_argument('log_file', help='The file to log', type=str)

    args = parser.parse_args()

    if args.pre_days <= 0:
        parser.print_help()
        sys.exit(0)

    check_test_results(args.pre_days, args.log_file)

if __name__ == "__main__":
    main()
