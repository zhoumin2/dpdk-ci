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

def main():
    if len(sys.argv) != 2:
        sys.exit(0)

    mailaddr = sys.argv[1]
    #print(mailaddr)
    if not is_contain_chinese(mailaddr):
        #print("not contain chinese")
        print(mailaddr)
        return

    a = mailaddr.find("<")
    b = mailaddr.find(">")
    #print(a, b)
    if a == -1 or b == -1 or b < a:
        #print("cannot found '<' and '>'")
        print(mailaddr)
        return

    print(mailaddr[a + 1 : b])

if __name__ == "__main__":
    main()
