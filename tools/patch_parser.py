#!/usr/bin/env python3

import itertools
import sys
from configparser import ConfigParser
from typing import List, Dict, Set


def get_patch_files(patch_file: str) -> List[str]:
    with open(patch_file, 'r') as f:
        lines = list(itertools.takewhile(
            lambda line: line.strip().endswith('+') or line.strip().endswith('-'),
            itertools.dropwhile(
                lambda line: not line.strip().startswith("---"),
                f.readlines()
            )
        ))
        filenames = map(lambda line: line.strip().split(' ')[0], lines)
        # takewhile includes the --- which starts the filenames
        return list(filenames)[1:]


def get_all_files_from_patches(patch_files: List[str]) -> Set[str]:
    return set(itertools.chain.from_iterable(map(get_patch_files, patch_files)))


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


if len(sys.argv) < 3:
    print("usage: patch_parser.py <path to patch_parser.cfg> <patch file>...")
    exit(1)

conf_obj = ConfigParser()
conf_obj.read(sys.argv[1])

patch_files = get_all_files_from_patches(sys.argv[2:])
dir_attrs = get_dictionary_attributes_from_config_file(conf_obj)
priority_list = parse_comma_delimited_list_from_string(conf_obj['Priority']['priority_list'])

unordered_tags: Set[str] = get_tags_for_patches(patch_files, dir_attrs)
ordered_tags: List[str] = [tag for tag in priority_list if tag in unordered_tags]

print("\n".join(ordered_tags))
