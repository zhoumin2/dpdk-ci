#! /bin/sh -e

# BSD LICENSE
#
# Copyright 2016 6WIND S.A.
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
#   * Neither the name of 6WIND S.A. nor the names of its
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

print_usage () {
	cat <<- END_OF_HELP
	usage: $(basename $0) < email

	Filter out email from stdin if does not match patch criterias.
	END_OF_HELP
}

while getopts h arg ; do
	case $arg in
		h ) print_usage ; exit 0 ;;
		? ) print_usage ; exit 1 ;;
	esac
done

if [ -t 0 ] ; then
	echo 'nothing to read on stdin' >&2
	exit 0
fi

fifo=/tmp/$(basename $0 sh)$$
mkfifo $fifo
trap "rm -f $fifo" INT EXIT

parse ()
{
	gitsend=false
	patchsubject=false
	content=false
	linenum=0
	minusline=false
	plusline=false
	atline=false
	binary=false
	done=false
	while IFS= read -r line ; do
		printf '%s\n' "$line"
		set -- $line
		if ! $content ; then
			[ "$1" != 'X-Mailer:' -o "$2" != 'git-send-email' ] || gitsend=true
			if echo "$line" | grep -qa '^Subject:.*\[PATCH' ; then
				subject=$(echo "$line" | sed 's,^Subject:[[:space:]]*,,')
				while [ -n "$subject" ] ; do
					echo "$subject" | grep -q '^\[' || break
					if echo "$subject" | grep -q '^\[PATCH' ; then
						patchsubject=true
						break
					fi
					subject=$(echo "$subject" | sed 's,^[^]]*\][[:space:]]*,,')
				done
			fi
			[ -n "$line" ] || content=true
		elif ! $done ; then
			$gitsend || $patchsubject || break
			[ "$1" != '---' ] || minusline=true
			[ "$1" != '+++' ] || plusline=true
			[ "$1" != '@@' ] || atline=true
			[ "$1 $2 $3" != 'GIT binary patch' ] || binary=true
			if ($minusline && $plusline && $atline) || $binary ; then
				echo 1 >$fifo
				done=true
				cat
				break
			fi
			linenum=$(($linenum + 1))
			[ $linenum -lt 999 ] || break
		fi
	done
	$done || echo 0 >$fifo
	exec >&-
}

waitparsing ()
{
	result=$(cat $fifo)
	[ "$result" = 0 ] || cat
}

parse | waitparsing
