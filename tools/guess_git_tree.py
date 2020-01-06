#!/usr/bin/env python

# SPDX-License-Identifier: (BSD-3-Clause AND GPL-2.0-or-later AND MIT)
# Copyright 2019 Mellanox Technologies, Ltd

import os
import sys
import re
import argparse
import fnmatch

from requests.exceptions import HTTPError

from git_pw import config
from git_pw import api
from git_pw import utils

"""
Description:
This script uses the git-pw API to retrieve Patchwork's
series/patches, and then find a tree/repo that best matches them,
depending on which files were changed in their diffs and using
the rules specified in the MAINTAINERS file.
If more than one tree was matched, a common tree (based on the
longest common prefix) will be chosen from the list.

Configurations:
The script uses tokens for authentication.
If the arguments pw_{server,project,token} aren't passed, the environment
variables PW_{SERVER,PROJECT,TOKEN} should be set. If not, the script will try
to load the git configurations pw.{server,project,token}.

Example usage:
    ./guess-git-tree.py --command list_trees_for_series 2054
    ./guess-git-tree.py --command list_trees_for_patch 2054

Or if you want to use inside other scripts:

    import os
    from guess_git_tree import (Maintainers, GitPW, Diff)
    _git_pw = GitPW({
        'pw_server': os.environ.get('PW_SERVER'),
        'pw_project': os.environ.get('PW_PROJECT'),
        'pw_token': os.environ.get('PW_TOKEN')})

    maintainers = Maintainers()
    patch_id = 52199
    files = Diff.find_filenames(_git_pw.api_get('patches', patch_id)['diff'])
    tree = maintainers.get_tree(files)
"""


MAINTAINERS_FILE_PATH = os.environ.get('MAINTAINERS_FILE_PATH')
if not MAINTAINERS_FILE_PATH:
    print('MAINTAINERS_FILE_PATH is not set.')
    sys.exit(1)


class GitPW(object):
    CONF = config.CONF
    CONF.debug = False

    def __init__(self, conf_obj=None):
        # Configure git-pw.
        conf_keys = ['server', 'project', 'token']
        for key in conf_keys:
            value = conf_obj.get('pw_{}'.format(key))
            if not value:
                print('--pw_{} is a required git-pw configuration'.format(key))
                sys.exit(1)
            else:
                setattr(self.CONF, key, value)

    def api_get(self, resource_type, resource_id):
        """Retrieve an API resource."""
        try:
            return api.detail(resource_type, resource_id)
        except HTTPError as err:
            if '404' in str(err):
                sys.exit(1)
            else:
                raise


class Diff(object):

    @staticmethod
    def find_filenames(diff):
        """Find file changes in a given diff.

        Source: https://github.com/getpatchwork/patchwork/blob/master/patchwork/parser.py
        Changes from source:
            - Moved _filename_re into the method.
            - Reduced newlines.
        """
        _filename_re = re.compile(r'^(---|\+\+\+) (\S+)')
        # normalise spaces
        diff = diff.replace('\r', '')
        diff = diff.strip() + '\n'
        filenames = {}
        for line in diff.split('\n'):
            if len(line) <= 0:
                continue
            filename_match = _filename_re.match(line)
            if not filename_match:
                continue
            filename = filename_match.group(2)
            if filename.startswith('/dev/null'):
                continue
            filename = '/'.join(filename.split('/')[1:])
            filenames[filename] = True
        filenames = sorted(filenames.keys())
        return filenames


class Maintainers(object):

    file_regex = r'F:\s(.*)'
    tree_regex = r'T: git:\/\/dpdk\.org(?:\/next)*\/(.*)'
    section_regex = r'([^\n]*)\n-+.*?(?=([^\n]*\n-+)|\Z)'
    subsection_regex = r'[^\n](?:(?!\n{{2}}).)*?^F: {}(?:(?!\n{{2}}).)*'

    def __init__(self):
        with open(MAINTAINERS_FILE_PATH) as fd:
            self.maintainers_txt = fd.read()
        # Add wildcard symbol at the end of lines where missing.
        self.maintainers_txt = re.sub(
                r'/$', '/*', self.maintainers_txt,
                count=0, flags=re.MULTILINE)
        # This matches the whole section that starts with:
        # Section Name
        # ------------
        self.sections = list(re.finditer(
                self.section_regex,
                self.maintainers_txt,
                re.DOTALL | re.MULTILINE))
        # This matches all the file patterns in the maintainers file.
        self.file_patterns = re.findall(
                self.file_regex, self.maintainers_txt, re.MULTILINE)
        # Save already matched patterns.
        self.matched = {}

    def get_tree(self, files):
        """
        Return a git tree that matches a list of files."""
        tree_list = []
        for _file in files:
            _tree = self._get_tree(_file)
            # No identified tree for a file means that it should go through
            # the main repository.
            if not _tree:
                _tree = 'dpdk'
            tree_list.append(_tree)
        tree = self.get_common_denominator(tree_list)
        if tree == '':
            tree = 'dpdk'
        return tree

    def _get_tree(self, filename):
        """
        Find a git tree that matches a filename from the maintainers file.
        The search stops at the first match.
        """
        tree = None
        # Check if we already tried to match with this pattern.
        for pat in self.matched.keys():
            if fnmatch.fnmatch(filename, pat):
                return self.matched[pat]

        # Find a file matching pattern.
        matching_pattern = None
        for pat in self.file_patterns:
            # This regex matches a lot of files and trees. Ignore it.
            if 'doc/*' in pat:
                continue
            if fnmatch.fnmatch(filename, pat):
                matching_pattern = pat
                break
        if not matching_pattern:
            return None

        found_match = False
        # Find the block containing filename.
        regex = self.subsection_regex.format(re.escape(matching_pattern))
        subsection_match = re.findall(
                regex,
                self.maintainers_txt,
                re.DOTALL | re.MULTILINE)
        if len(subsection_match):
            subsection = subsection_match[-1]
            # Look for a tree around the file path.
            tree_match = re.search(
                    self.tree_regex, subsection)
            if tree_match:
                tree = tree_match.group(1)
                self.matched[matching_pattern] = tree
                found_match = True

        # If no tree was specified in the subsection containing filename,
        # try to find a tree after the section name.
        if not found_match:
            for section in self.sections:
                if re.search(re.escape(matching_pattern), section.group(0)):
                    tree_match = re.search(
                            self.tree_regex,
                            section.group(0).split('\n\n')[0])
                    if tree_match:
                        tree = tree_match.group(1)

        self.matched[matching_pattern] = tree
        return tree

    def get_common_denominator(self, tree_list):
        """Finds a common tree by finding the longest common prefix.
        Examples for expected output:
          dpdk-next-virtio + dpdk = dpdk
          dpdk-next-net-intel + dpdk = dpdk
          dpdk-next-crypto + dpdk-next-virtio = dpdk
          dpdk-next-net-intel + dpdk-next-net-mlx = dpdk-next-net
        """
        # Make sure the list is unique.
        tree_list = list(set(tree_list))

        # Rename dpdk-next-virtio internally to match dpdk-next-net
        _tree_list = [
                tree.replace('dpdk-next-virtio', 'dpdk-next-net-virtio')
                for tree in tree_list]
        common_prefix = \
            os.path.commonprefix(_tree_list).rstrip('-').replace(
                    'dpdk-next-net-virtio', 'dpdk-next-virtio')
        # There is no 'dpdk-next' named tree.
        if common_prefix == 'dpdk-next':
            common_prefix = 'dpdk'
        return common_prefix


if __name__ == '__main__':
    """Main procedure."""
    parser = argparse.ArgumentParser()
    git_pw_conf_parser = parser.add_argument_group('git-pw configurations')
    options_parser = parser.add_argument_group('optional arguments')

    options_parser.add_argument(
            '--command',
            choices=(
                'list_trees_for_patch',
                'list_trees_for_series'),
            required=True, help='Command to perform')

    git_pw_conf_parser.add_argument(
            '--pw_server', type=str,
            default=os.environ.get(
                'PW_SERVER', utils.git_config('pw.server')),
            help='Patchwork server')
    git_pw_conf_parser.add_argument(
            '--pw_project', type=str,
            default=os.environ.get(
                'PW_PROJECT', utils.git_config('pw.project')),
            help='Patchwork project')
    git_pw_conf_parser.add_argument(
            '--pw_token', type=str,
            default=os.environ.get('PW_TOKEN', utils.git_config('pw.token')),
            help='Authentication token')

    parser.add_argument(
            'id', type=int, help='patch/series id')

    args = parser.parse_args()

    command = args.command
    _id = args.id

    # Pass the needed configurations to git-pw.
    conf_obj = {
            key: value for key, value in args.__dict__.items() if
            key.startswith('pw_')}
    _git_pw = GitPW(conf_obj)

    maintainers = Maintainers()

    patch_list = []
    if command == 'list_trees_for_patch':
        patch_list.append(_git_pw.api_get('patches', _id))
    elif command == 'list_trees_for_series':
        series = _git_pw.api_get('series', _id)
        patch_list = [
                _git_pw.api_get('patches', patch['id'])
                for patch in series['patches']]

    files = []
    for patch in patch_list:
        files += Diff.find_filenames(patch['diff'])
    print(maintainers.get_tree(files))
