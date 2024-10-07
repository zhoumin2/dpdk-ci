#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2023 University of New Hampshire

import argparse
import datetime
import json
import re
import requests
from typing import Dict, List, Optional, Set

DPDK_PATCHWORK_EVENTS_API_URL = "http://patches.dpdk.org/api/events/"


class JSONSetEncoder(json.JSONEncoder):
    """Custom JSON encoder to handle sets.

    Pythons json module cannot serialize sets so this custom encoder converts
    them into lists.
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

    Args:
        desired_contexts: List of all contexts to search for in the bodies of
            the comments
        time_since: Get all comments since this timestamp
        pw_api_url: URL for events endpoint of the patchwork API to use for collecting
            comments and comment data

    Attributes:
        collection_of_retests: A dictionary that maps patch series IDs to the
            set of contexts to be retested for that patch series.
        regex: regex used for collecting the contexts from the comment body.
        last_comment_timestamp: timestamp of the most recent comment that was
            processed
    """

    _desired_contexts: List[str]
    _time_since: str
    _pw_api_url: str
    collection_of_retests: Dict[str, Dict[str, Set]] = {}
    last_comment_timestamp: Optional[str] = None
    # The tag we search for in comments must appear at the start of the line
    # and is case sensitive. After this tag we expect a comma separated list
    # of valid DPDK patchwork contexts.
    #
    # VALID MATCHES:
    #   Recheck-request: iol-unit-testing, iol-something-else, iol-one-more,
    #   Recheck-request: iol-unit-testing,iol-something-else, iol-one-more
    #   Recheck-request: iol-unit-testing, iol-example, iol-another-example,
    #   more-intel-testing
    # INVALID MATCHES:
    #   Recheck-request: iol-unit-testing,  intel-example-testing
    #   Recheck-request: iol-unit-testing iol-something-else,iol-one-more,
    #   Recheck-request: iol-unit-testing,iol-something-else,iol-one-more,
    #
    #   more-intel-testing
    regex: str = "^Recheck-request: ((?:[a-zA-Z0-9-_]+(?:, ?\n?)?)+)"

    def __init__(
        self, desired_contexts: List[str], time_since: str, pw_api_url: str
    ) -> None:
        self._desired_contexts = desired_contexts
        self._time_since = time_since
        self._pw_api_url = pw_api_url

    def process_reruns(self) -> None:
        patchwork_url = f"{self._pw_api_url}?since={self._time_since}"
        comment_request_info = []
        for item in [
            "&category=cover-comment-created",
            "&category=patch-comment-created",
        ]:
            response = requests.get(patchwork_url + item)
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

            labels_to_rerun = self.get_test_names(content)

            # appending to the list if it already exists, or creating it if it
            # doesn't
            if labels_to_rerun:
                self.collection_of_retests[patch_id] = self.collection_of_retests.get(
                    patch_id, {"contexts": set()}
                )
                self.collection_of_retests[patch_id]["contexts"].update(labels_to_rerun)

    def get_test_names(self, email_body: str) -> Set[str]:
        """Uses the regex in the class to get the information from the email.

        When it gets the test names from the email, it will all be in one
        capture group. We expect a comma separated list of patchwork labels
        to be retested.

        Returns:
            A set of contexts found in the email that match your list of
            desired contexts to capture. We use a set here to avoid duplicate
            contexts.
        """
        rerun_section = re.findall(self.regex, email_body, re.MULTILINE)
        if not rerun_section:
            return set()
        rerun_list = list(map(str.strip, rerun_section[0].split(",")))
        return set(filter(lambda x: x and x in self._desired_contexts, rerun_list))

    def write_output(self, file_name: str) -> None:
        """Output class information.

        Takes the collection_of_retests and last_comment_timestamp and outputs
        them into either a json file or stdout.

        Args:
            file_name: Name of the file to write the output to. If this is set
            to "-" then it will output to stdout.
        """

        output_dict = {
            "retests": self.collection_of_retests,
            "last_comment_timestamp": self.last_comment_timestamp,
        }
        if file_name == "-":
            print(json.dumps(output_dict, indent=4, cls=JSONSetEncoder))
        else:
            with open(file_name, "w") as file:
                file.write(json.dumps(output_dict, indent=4, cls=JSONSetEncoder))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Help text for getting reruns")
    parser.add_argument(
        "-ts",
        "--time-since",
        dest="time_since",
        required=True,
        help='Get all patches since this timestamp (yyyy-mm-ddThh:mm:ss.SSSSSS).',
    )
    parser.add_argument(
        "--contexts",
        dest="contexts_to_capture",
        nargs="*",
        required=True,
        help='List of patchwork contexts you would like to capture.',
    )
    parser.add_argument(
        "-o",
        "--out-file",
        dest="out_file",
        help=(
            'Output file where the list of reruns and the timestamp of the '
            'last comment in the list of comments is sent. If this is set '
            'to "-" then it will output to stdout (default: -).'
        ),
        default="-",
    )
    parser.add_argument(
        "-u",
        "--patchwork-url",
        dest="pw_url",
        help=(
            'URL for the events endpoint of the patchwork API that will be used to '
            f'collect retest requests (default: {DPDK_PATCHWORK_EVENTS_API_URL})'
        ),
        default=DPDK_PATCHWORK_EVENTS_API_URL
    )
    args = parser.parse_args()
    rerun_processor = RerunProcessor(
        args.contexts_to_capture, args.time_since, args.pw_url
    )
    rerun_processor.process_reruns()
    rerun_processor.write_output(args.out_file)
