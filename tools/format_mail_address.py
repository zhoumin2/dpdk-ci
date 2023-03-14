# -*- coding: utf-8 -*-
#!/bin/python

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

import sys

def is_contain_chinese(check_str):
    for ch in check_str:
        if u'\u4e00' <= ch <= u'\u9fff':
            return True
    return False

def is_contain_8bit(check_str):
    return len(check_str) != len(check_str.encode())

def main():
    if len(sys.argv) != 2:
        sys.exit(0)

    mailaddr = sys.argv[1]
    #print(mailaddr)
    a = mailaddr.find("<")
    b = mailaddr.find(">")

    if is_contain_chinese(mailaddr):
        if a == -1 or b == -1 or b <= a:
            print(mailaddr)
        else:
            print(mailaddr[a + 1 : b])
        return

    if is_contain_8bit(mailaddr):
        if a == -1 or b == -1 or b <= a:
            print(mailaddr)
        else:
            print(mailaddr[a + 1 : b])
        return

    print(mailaddr)

if __name__ == "__main__":
    main()
