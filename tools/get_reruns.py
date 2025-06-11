#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2023 University of New Hampshire

import argparse
import datetime
import json
import re
from json import JSONEncoder
from typing import Dict, List, Set, Optional, Tuple

import requests


class JSONSetEncoder(JSONEncoder):
    """Custom JSON encoder to handle sets.

    Pythons json module cannot serialize sets so this custom encoder converts
    them into lists.

    Args:
        JSONEncoder: JSON encoder from the json python module.
    """

    def default(self, input_object):
        if isinstance(input_object, set):
            return list(input_object)
        return input_object


class RerunProcessor:
    """Class for finding reruns inside an email using the patchworks events
    API.

    The idea of this class is to use regex to find certain patterns that
    represent desired contexts to rerun.

    Arguments:
        desired_contexts: List of all contexts to search for in the bodies of
            the comments
        time_since: Get all comments since this timestamp

    Attributes:
        collection_of_retests: A dictionary that maps patch series IDs to the
            set of contexts to be retested for that patch series.
        regex: regex used for collecting the contexts from the comment body.
        last_comment_timestamp: timestamp of the most recent comment that was
            processed
    """
    _VALID_ARGS: Set[str] = set(["rebase"])

    _desired_contexts: List[str]
    _time_since: str
    collection_of_retests: Dict[str, Dict[str, Set]] = {}
    last_comment_timestamp: Optional[str] = None
    # ^ is start of line
    # ((?:(?:[\\w-]+=)?[\\w-]+(?:, ?\n?)?)+) is a capture group that gets all
    #   test labels and key-value pairs after "Recheck-request: "
    #   (?:[\\w-]+=)? optionally grabs a key followed by an equals sign
    #       (no space)
    #       [\\w-] (expanded to "(:?[a-zA-Z0-9-_]+)" ) means 1 more of any
    #           character in the ranges a-z, A-Z, 0-9, or the characters
    #               '-' or '_'
    #       (?:, ?\n?)? means 1 or none of this match group which expects
    #           exactly 1 comma followed by 1 or no spaces followed by
    #           1 or no newlines.
    # VALID MATCHES:
    #   Recheck-request: iol-unit-testing, iol-something-else, iol-one-more,
    #   Recheck-request: iol-unit-testing,iol-something-else, iol-one-more
    #   Recheck-request: iol-unit-testing, iol-example, iol-another-example,
    #   more-intel-testing
    #   Recheck-request: x=y, rebase=latest, iol-unit-testing, iol-additional-example
    # INVALID MATCHES:
    #   Recheck-request: iol-unit-testing,  intel-example-testing
    #   Recheck-request: iol-unit-testing iol-something-else,iol-one-more,
    #   Recheck-request: iol-unit-testing, rebase = latest
    #   Recheck-request: iol-unit-testing,iol-something-else,iol-one-more,
    #   more-intel-testing
    regex: str = "^Recheck-request: ((?:(?:[\\w-]+=)?[\\w-]+(?:, ?\n?)?)+)"
    last_comment_timestamp: str

    def __init__(self, desired_contexts: List[str], time_since: str, multipage: bool) -> None:
        self._desired_contexts = desired_contexts
        self._time_since = time_since
        self._multipage = multipage

    def process_reruns(self) -> None:
        patchwork_url = f"http://patches.dpdk.org/api/events/?since={self._time_since}"
        comment_request_info = []
        for item in [
            "&category=cover-comment-created",
            "&category=patch-comment-created",
        ]:
            response = requests.get(patchwork_url + item)
            response.raise_for_status()
            comment_request_info.extend(response.json())

            while 'next' in response.links and self._multipage:
                response = requests.get(response.links['next']['url'])
                response.raise_for_status()
                comment_request_info.extend(response.json())

        rerun_processor.process_comment_info(comment_request_info)

    def process_comment_info(self, list_of_comment_blobs: List[Dict]) -> None:
        """Takes the list of json blobs of comment information and associates
        them with their patches.

        Collects retest labels from a list of comments on patches represented
        inlist_of_comment_blobs and creates a dictionary that associates them
        with their corresponding patch series ID. The labels that need to be
        retested are collected by passing the comments body into
        get_test_names() method. This method also updates the current UTC
        timestamp for the processor to the current time.

        Args:
            list_of_comment_blobs: a list of JSON blobs that represent comment
            information
        """

        list_of_comment_blobs = sorted(
            list_of_comment_blobs,
            key=lambda x: datetime.datetime.fromisoformat(x["date"]),
            reverse=True,
        )

        if list_of_comment_blobs:
            most_recent_timestamp = datetime.datetime.fromisoformat(
                list_of_comment_blobs[0]["date"]
            )
            # exclude the most recent
            most_recent_timestamp = most_recent_timestamp + datetime.timedelta(
                microseconds=1
            )
            self.last_comment_timestamp = most_recent_timestamp.isoformat()

        for comment in list_of_comment_blobs:
            # before we do any parsing we want to make sure that we are dealing
            # with a comment that is associated with a patch series
            payload_key = "cover"
            if comment["category"] == "patch-comment-created":
                payload_key = "patch"
            patch_series_arr = requests.get(
                comment["payload"][payload_key]["url"]
            ).json()["series"]
            if not patch_series_arr:
                continue
            patch_id = patch_series_arr[0]["id"]

            comment_info = requests.get(comment["payload"]["comment"]["url"])
            comment_info.raise_for_status()
            content = comment_info.json()["content"]

            (args, labels_to_rerun) = self.get_test_names_and_parameters(content)

            # Accept either filtered labels or arguments.
            if labels_to_rerun or (args and self._VALID_ARGS.issuperset(args.keys())):
                # Get or insert a new retest request into the dict.
                self.collection_of_retests[patch_id] = \
                    self.collection_of_retests.get(
                        patch_id, {"contexts": set(), "arguments": dict()}
                    )

                req = self.collection_of_retests[patch_id]

                # Update the fields.
                req["contexts"].update(labels_to_rerun)
                req["arguments"].update(args)

    def get_test_names_and_parameters(
        self, email_body: str
    ) -> Tuple[Dict[str, str], Set[str]]:
        """Uses the regex in the class to get the information from the email.

        When it gets the test names from the email, it will be split into two
        capture groups. We expect a comma separated list of patchwork labels
        to be retested, and another comma separated list of key-value pairs
        which are arguments for the retest.

        Returns:
            A set of contexts found in the email that match your list of
            desired contexts to capture. We use a set here to avoid duplicate
            contexts.
        """
        rerun_list: Set[str] = set()
        params_dict: Dict[str, str] = dict()

        match: List[str] = re.findall(self.regex, email_body, re.MULTILINE)
        if match:
            items: List[str] = list(map(str.strip, match[0].split(",")))

            for item in items:
                if '=' in item:
                    sides = item.split('=')
                    params_dict[sides[0]] = sides[1]
                else:
                    rerun_list.add(item)

        return (params_dict, set(filter(lambda x: x in self._desired_contexts, rerun_list)))

    def write_to_output_file(self, file_name: str) -> None:
        """Write class information to a JSON file.

        Takes the collection_of_retests and last_comment_timestamp and outputs
        them into a json file.

        Args:
            file_name: Name of the file to write the output to.
        """

        output_dict = {
            "retests": self.collection_of_retests,
            "last_comment_timestamp": self.last_comment_timestamp,
        }
        with open(file_name, "w") as file:
            file.write(json.dumps(output_dict, indent=4, cls=JSONSetEncoder))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Help text for getting reruns")
    parser.add_argument(
        "-ts",
        "--time-since",
        dest="time_since",
        required=True,
        help="Get all patches since this many days ago (default: 5)",
    )
    parser.add_argument(
        "--contexts",
        dest="contexts_to_capture",
        nargs="*",
        required=True,
        help="List of patchwork contexts you would like to capture",
    )
    parser.add_argument(
        "-o",
        "--out-file",
        dest="out_file",
        help=(
            "Output file where the list of reruns and the timestamp of the"
            "last comment in the list of comments"
            "(default: rerun_requests.json)."
        ),
        default="rerun_requests.json",
    )
    parser.add_argument(
        "-m",
        "--multipage",
        action="store_true",
        help="When set, searches all pages of patch/cover comments in the query."
    )
    args = parser.parse_args()
    rerun_processor = RerunProcessor(args.contexts_to_capture, args.time_since, args.multipage)
    rerun_processor.process_reruns()
    rerun_processor.write_to_output_file(args.out_file)
