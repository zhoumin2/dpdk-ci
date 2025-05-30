#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2016 6WIND S.A.

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
			if echo "$line" | grep -qaE '^Subject:.*(PATCH|RFC)' ; then
				subject=$(echo "$line" | sed 's,^Subject:[[:space:]]*,,')
				while [ -n "$subject" ] ; do
					echo "$subject" | grep -q '^\[' || break
					if echo "$subject" | grep -qE '^\[(RESEND |)(RFC |)(PATCH |)' ; then
						echo "find subject: $subject"
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
			[ "$1 $2" != 'mode change' ] || mode_change=true
			[ "$1 $2" != 'old mode' ] || old_mode=true
			[ "$1 $2" != 'new mode' ] || new_mode=true
			if ($minusline && $plusline && $atline) || $binary || ($mode_change && $old_mode && $new_mode) ; then
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
