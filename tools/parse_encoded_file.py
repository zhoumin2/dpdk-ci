# -*- coding: utf-8 -*-
#!/bin/python

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

import codecs
import email.header
import re
import sys

def decode_mime_words(s):
    return u''.join(
        word.decode(encoding or 'utf8') if isinstance(word, bytes) else word
        for word, encoding in email.header.decode_header(s))

def parse_decoded_file(ori_path, new_path):
    fp = open(ori_path)
    if fp == None:
        print("open %s failed" % (ori_path))
        exit(1)
    
    pattern = re.compile('=\?utf-8\?[bq]\?.*\?=', re.IGNORECASE)

    cached = {}
    lines = []
    line = fp.readline()
    while line:
        ret = pattern.findall(line) 
        if len(ret) == 0:
            lines.append(line)
            line = fp.readline()
            continue

        for item in ret:
            if item not in cached:
                cached[item] = decode_mime_words(item)
            line = line.replace(item, cached[item])
        lines.append(line)

        line = fp.readline()
    fp.close()

    fp = codecs.open(new_path, 'w', encoding='utf-8') 
    if fp == None:
        print("open %s failed" % (new_path))
        exit(1)

    for line in lines:
        fp.write(line)
    fp.close()

def main():
    if len(sys.argv) != 3:
        print("Usage: %s ori_file new_file" % (sys.argv[0]))
        exit(1)

    parse_decoded_file(sys.argv[1], sys.argv[2])

if __name__ == "__main__":
    main()
