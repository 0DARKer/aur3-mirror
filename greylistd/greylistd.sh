#!/bin/bash

client=/usr/bin/greylist
daemon=/usr/sbin/greylistd
rundir=/var/run/greylistd
datadir=/var/lib/greylistd
pidfile=$rundir/pid
socket=$rundir/socket
user=greylist

. /etc/rc.conf
. /etc/rc.d/functions


# See if the daemon is present
test -x "$daemon" || exit 0

case "$1" in
    start)
	stat_busy "Starting Greylistd"

	if [ -e "$socket" ]
	then
	    echo "$0:"
	    echo "  Another instance of \`${daemon##*/}' seems to be running."
	    echo "  If this is not the case, please remove \"$socket\"."
            stat_fail
	    exit 1
	fi

	echo -n "Starting greylisting daemon: "
	start-stop-daemon --start --background \
	    --chuid "$user" \
	    --pidfile "$pidfile" --make-pidfile \
	    --exec "$daemon" &&
	    echo "${daemon##*/}."
        add_daemon greylistd
        stat_done
	;;


    stop)
	echo -n "Stopping greylisting daemon: "
	start-stop-daemon --stop --pidfile "$pidfile" &&
	    rm -f "$pidfile" &&
	    echo "${daemon##*/}."
        rm_daemon greylistd
        stat_done
	;;


    reload|force-reload)
	"$client" reload
	;;

    status)
	"$client" stats
	;;


    restart)
	$0 stop
	sleep 2
	$0 start
	;;


    *)
	echo "Usage: $0 {start|stop|restart|reload|force-reload|status}" >&2
	exit 1
	;;
esac

exit 0

