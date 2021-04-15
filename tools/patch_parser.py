#!/usr/bin/env python3

import argparse
from configparser import ConfigParser
from typing import List, Dict, Set

import itertools
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

try:
    import whatthepatch
except ImportError:
    print("Please install whatthepatch, a patch parsing library", file=sys.stderr)
    exit(1)


def get_changed_files_in_patch(patch_file: str) -> List[str]:
    with open(patch_file, 'r') as f:
        filenames = map(lambda diff: diff.header.new_path, whatthepatch.parse_patch(f.read()))
        return list(filenames)


def get_all_files_from_patches(patch_files: List[str]) -> Set[str]:
    return set(itertools.chain.from_iterable(map(get_changed_files_in_patch, patch_files)))


def parse_comma_delimited_list_from_string(mod_str: str) -> List[str]:
    return list(map(str.strip, mod_str.split(',')))


def get_dictionary_attributes_from_config_file(conf_obj: ConfigParser) -> Dict[str, Set[str]]:
    return {
        directory: parse_comma_delimited_list_from_string(module_string) for directory, module_string in
        conf_obj['Paths'].items()
    }


def get_tags_for_patch_file(patch_file: str, dir_attrs: Dict[str, Set[str]]) -> Set[str]:
    return set(itertools.chain.from_iterable(
        tags for directory, tags in dir_attrs.items() if patch_file.startswith(directory)
    ))


def get_tags_for_patches(patch_files: Set[str], dir_attrs: Dict[str, Set[str]]) -> Set[str]:
    return set(itertools.chain.from_iterable(
        map(lambda patch_file: get_tags_for_patch_file(patch_file, dir_attrs), patch_files)
    ))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Takes a patch file and a config file and creates a list of tags for that patch')
    parser.add_argument('config_file_path', help='The path to patch_parser.cfg', default='config/patch_parser.cfg')
    parser.add_argument('patch_file_paths', help='A list of patch files', type=str, metavar='patch file', nargs='+')

    args = parser.parse_args()

    conf_obj = ConfigParser()
    conf_obj.read(args.config_file_path)

    patch_files = get_all_files_from_patches(args.patch_file_paths)
    dir_attrs = get_dictionary_attributes_from_config_file(conf_obj)
    priority_list = parse_comma_delimited_list_from_string(conf_obj['Priority']['priority_list'])

    unordered_tags: Set[str] = get_tags_for_patches(patch_files, dir_attrs)
    ordered_tags: List[str] = [tag for tag in priority_list if tag in unordered_tags]

    print("\n".join(ordered_tags))
