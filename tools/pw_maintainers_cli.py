#!/usr/bin/env python

# SPDX-License-Identifier: (BSD-3-Clause AND GPL-2.0-or-later AND MIT)
# Copyright 2019 Mellanox Technologies, Ltd

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
    ./pw_maintainers_cli.py --type series list-trees 2054
    ./pw_maintainers_cli.py --type patch list-trees 2054
    ./pw_maintainers_cli.py --type patch list-maintainers 2054

Or if you want to use inside other scripts:

    import os
    from pw_maintainers_cli import (Maintainers, GitPW, Diff)
    _git_pw = GitPW({
        'pw_server': os.environ.get('PW_SERVER'),
        'pw_project': os.environ.get('PW_PROJECT'),
        'pw_token': os.environ.get('PW_TOKEN')})

    maintainers = Maintainers()
    patch_id = 52199
    files = Diff.find_filenames(_git_pw.api_get('patches', patch_id)['diff'])
    tree_url = maintainers.get_tree(files)
    tree_name = tree_url.split('/')[-1]
    maintainers = maintainers.get_maintainers(tree_url)
"""

import os
import sys
import re
import argparse
import fnmatch

from requests.exceptions import HTTPError

from git_pw import config
from git_pw import api
from git_pw import utils
from git_pw import patch as git_pw_patch

MAINTAINERS_FILE_PATH = os.environ.get('MAINTAINERS_FILE_PATH')
if not MAINTAINERS_FILE_PATH:
    print('MAINTAINERS_FILE_PATH is not set.', file=sys.stderr)
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
                sys.exit('--pw_{} is a required git-pw configuration'.format(key))
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

    def set_delegate(self, patch_list, delegate, skip_delegated=False):
        """
        Set the delegate for a patch.
        This overrides the current delegate. If 'skip_delegated' is set to
        True, only set a delegate for patches that don't have one set already.

        Reference:
        https://github.com/getpatchwork/git-pw/blob/76b79097dc0a57/git_pw/patch.py#L167
        """
        users = api.index('users', [('q', delegate)])
        if len(users) != 1:
            # Zero or multiple users found
            print('Cannot choose a Patchwork user associated with {} to '
                  'delegate to.'.format(delegate, users), file=sys.stderr)
            return
        for patch in patch_list:
            if patch['delegate'] != None and \
                    (patch['delegate'].get('email') == users[0].get('email') or \
                    skip_delegated):
                print('Patch {} is already delegated to {}. '
                      'Skipping..'.format(
                          patch['id'], patch['delegate']['email']))
                continue
            print("Delegating patch {} to {}..".format(
                patch['id'], users[0]['email']))
            _ = api.update(
                    'patches', patch['id'], [('delegate', users[0]['id'])])
        return users[0].get('email')


class Diff(object):

    @staticmethod
    def find_filenames(diff):
        """Find file changes in a given diff.

        Source: https://github.com/getpatchwork/patchwork/blob/master/patchwork/parser.py
        Changes from source:
            - Moved _filename_re into the method.
            - Reduced newlines.
        """
        # sanity check diff
        # for patches without any diff, it will try to run diff.replace
        # while diff is None. just return an empty list
        if diff is None:
            return []
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
    tree_regex = r'T: (?P<url>git:\/\/dpdk\.org(?:\/next)*\/(?P<name>.*))'
    maintainer_regex = r'M:\s(.*)'
    section_regex = r'([^\n]*)\n-+.*?(?=([^\n]*\n-+)|\Z)'
    subsection_regex = r'[^\n](?:(?!\n{{2}}).)*?^{}: {}$(?:(?!\n{{2}}).)*'
    general_proj_admin_title = 'General Project Administration'

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

    def get_maintainers(self, tree):
        """
        Return a list of a tree's maintainers.
        """
        maintainers = []
        for section in self.sections:
            if section.group(1) == self.general_proj_admin_title:
                # Find the block containing the tree.
                regex = self.subsection_regex.format('T', re.escape(tree))
                subsection_match = re.findall(
                        regex,
                        section.group(0),
                        re.DOTALL | re.MULTILINE)
                if len(subsection_match):
                    subsection = subsection_match[-1]
                    # Look for maintainers
                    maintainers = re.findall(
                            self.maintainer_regex, subsection)
                    return maintainers
                break

    def get_tree(self, files):
        """
        Return a git tree that matches a list of files."""
        tree_list = []
        file_tree_map = {}
        for _file in files:
            _tree = self._get_tree(_file)
            # Having no tree means that we accept those changes going through a
            # subtree (e.g. release notes).
            if _tree:
                tree_list.append(_tree)
                file_tree_map[_file] = _tree
        tree = self.get_common_denominator(tree_list, file_tree_map)
        if not tree:
            tree = 'git://dpdk.org/dpdk'
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
        regex = self.subsection_regex.format('F', re.escape(matching_pattern))
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
                tree = tree_match.group('url')
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
                        tree = tree_match.group('url')

        self.matched[matching_pattern] = tree
        return tree

    def get_common_denominator(self, tree_list, file_tree_map):
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
        # There is no 'dpdk-next' named tree, remove files that belong
        # to 'drivers/common' and see if we find a tree.
        if common_prefix.endswith('dpdk-next'):
            common_prefix = self.get_filtered_tree(file_tree_map)
        elif common_prefix.endswith('/'):
            common_prefix = 'git://dpdk.org/dpdk'
        return common_prefix

    def get_common_files(self, files):
        match_list = []
        for f in files:
            if re.match(r"drivers\/common", f) is not None:
                match_list.append(f)
        return match_list

    def get_filtered_tree(self, file_tree_map):
        # Get list of files that are in 'drivers/common'
        common_list = self.get_common_files(file_tree_map.keys())
        for c in common_list:
            file_tree_map.pop(c, None)
        tree_list = list(set(file_tree_map.values()))
        if len(tree_list) == 1:
            return tree_list[0]
        return None


if __name__ == '__main__':
    """Main procedure."""
    parser = argparse.ArgumentParser()
    git_pw_conf_parser = parser.add_argument_group('git-pw configurations')
    required_args_parser = parser.add_argument_group('required arguments')

    required_args_parser.add_argument(
            '--type',
            choices=(
                'patch',
                'series'),
            required=True, help='Resource type.')

    git_pw_conf_parser.add_argument(
            '--pw-server', type=str,
            default=os.environ.get(
                'PW_SERVER', utils.git_config('pw.server')),
            help='Patchwork server')
    git_pw_conf_parser.add_argument(
            '--pw-project', type=str,
            default=os.environ.get(
                'PW_PROJECT', utils.git_config('pw.project')),
            help='Patchwork project')
    git_pw_conf_parser.add_argument(
            '--pw-token', type=str,
            default=os.environ.get('PW_TOKEN', utils.git_config('pw.token')),
            help='Authentication token')

    parser.add_argument(
            '--skip-delegated',
            action='store_true', required=False,
            help='Skip patches that are already delegated')
    parser.add_argument(
            'command',
            choices=[
                'list-trees', 'list-maintainers', 'set-pw-delegate'],
            help='Command to perform')
    parser.add_argument(
            'id', type=int, help='patch/series id')

    args = parser.parse_args()

    skip_delegated = args.skip_delegated
    command = args.command
    resource_type = args.type
    _id = args.id

    # Pass the needed configurations to git-pw.
    conf_obj = {
            key: value for key, value in args.__dict__.items() if
            key.startswith('pw_')}
    _git_pw = GitPW(conf_obj)

    maintainers = Maintainers()

    patch_list = []
    if resource_type == 'patch':
        patch_list.append(_git_pw.api_get('patches', _id))
    else:
        series = _git_pw.api_get('series', _id)
        patch_list = [
                _git_pw.api_get('patches', patch['id'])
                for patch in series['patches']]

    files = []
    for patch in patch_list:
        files += Diff.find_filenames(patch['diff'])

    tree = maintainers.get_tree(files)

    if command == 'list-trees':
        print(tree.split('/')[-1])
    if command in ['list-maintainers', 'set-pw-delegate']:
        maintainer_list = maintainers.get_maintainers(tree)
        if command == 'list-maintainers':
            print(*maintainer_list, sep='\n')
        elif command == 'set-pw-delegate':
            if len(maintainer_list) > 0:
                for maintainer in maintainer_list:
                    # Get the maintainer's email
                    try:
                        maintainer_email = re.match(
                                r".*\<(?P<email>.*)\>",
                                maintainer).group('email')
                    except AttributeError:
                        print("Unexpected format: '{}'".format(maintainer),
                                file=sys.stderr)
                    delegate = _git_pw.set_delegate(
                            patch_list, maintainer_email,
                            skip_delegated=skip_delegated)
                    if delegate != None:
                        break
            else:
                print('No maintainers matched. Not setting a delegate.',
                        file=sys.stderr)
