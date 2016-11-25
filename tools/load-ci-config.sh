#! /bin/echo must be loaded with .

# Load DPDK CI config and allow override
# from system file
test ! -r /etc/dpdk/ci.config ||
        . /etc/dpdk/ci.config
# from user file
test ! -r ~/.config/dpdk/ci.config ||
        . ~/.config/dpdk/ci.config
# from local file
test ! -r $(dirname $(readlink -m $0))/../.ciconfig ||
        . $(dirname $(readlink -m $0))/../.ciconfig

# The config files must export variables in the shell style
