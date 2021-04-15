#!/usr/bin/env python3

# BSD LICENSE
#
# Copyright(c) 2020 Intel Corporation. All rights reserved.
# Copyright © 2018[, 2019] The University of New Hampshire. All rights reserved.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#   * Neither the name of Intel Corporation nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
import sys
from enum import Enum

import itertools
from configparser import ConfigParser
from typing import List, Dict, Set
import argparse


def parse_comma_delimited_list_from_string(mod_str: str) -> List[str]:
    return list(map(str.strip, mod_str.split(',')))


def map_tags_to_tests(tags: List[str], test_map: Dict[str, List[str]]) -> Set[str]:
    """
    Returns a list that is the union of all of the map lookups.
    """
    try:
        return set(
            filter(lambda test: test != '', set(itertools.chain.from_iterable(map(lambda tag: test_map[tag], tags)))))
    except KeyError as e:
        print(f'Tag {e} is not present in tests_for_tag.cfg')
        exit(1)


class TestingType(Enum):
    functional = 'functional'
    performance = 'performance'

    def __str__(self):
        return self.value


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Take a template execution file and add the relevant tests'
                    ' for the given tags to it, creating a new file.')
    parser.add_argument('config_file_path', help='The path to tests_for_tag.cfg', default='config/tests_for_tag.cfg')
    parser.add_argument('template_execution_file', help='The path to the execution file to use as a template')
    parser.add_argument('output_path', help='The path to the output execution file')
    parser.add_argument('testing_type', type=TestingType, choices=list(TestingType),
                        help='What type of testing to create an execution file for')
    parser.add_argument('tags', metavar='tag', type=str, nargs='*', help='The tags to create an execution file for.')

    args = parser.parse_args()

    tag_to_test_map_parser = ConfigParser()
    tag_to_test_map_parser.read(args.config_file_path)

    template_execution_file_parser = ConfigParser()
    template_execution_file_parser.read(args.template_execution_file)

    test_map = {key: parse_comma_delimited_list_from_string(value.strip()) for key, value in
                tag_to_test_map_parser[str(args.testing_type)].items()}

    tests = map_tags_to_tests(args.tags, test_map)

    try:
        output_file = open(args.output_path, 'x')
    except FileExistsError:
        output_file = open(args.output_path, 'w')

    for execution_plan in template_execution_file_parser:
        # The DEFAULT section is always present and contains top-level items, so it needs to be ignored
        if execution_plan != 'DEFAULT':
            test_allowlist = parse_comma_delimited_list_from_string(
                template_execution_file_parser[execution_plan]['test_suites'])
            tests_to_run = list(set(test_allowlist).intersection(tests))
            tests_to_run.sort()
            template_execution_file_parser[execution_plan]['test_suites'] = ", ".join(tests_to_run)

            if args.testing_type == TestingType.functional:
                template_execution_file_parser[execution_plan]['parameters'] += ':func=true:perf=false'
            elif args.testing_type == TestingType.performance:
                template_execution_file_parser[execution_plan]['parameters'] += ':func=false:perf=true'
            else:
                # This code should be unreachable, since this is checked at the top of the file
                print("Fatal error: testing type is neither performance nor functional", file=sys.stderr)
                exit(1)

    template_execution_file_parser.write(output_file)
