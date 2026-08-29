#!/bin/sh
# /usr/bin/scut-autologin.sh
# SCUT campus network auto-login daemon: detection and keep-alive loop.
#
# The login protocol itself lives in /usr/lib/scut-autologin/login.sh,
# which is sourced below.
#
# Config (UCI /etc/config/scut-autologin):
#   main.{enabled,username,password,interval,check_host,portal_host,suffix,timeout}

. /lib/functions.sh

CFG=scut-autologin
LOGTAG=scut-autologin
PIDFILE=/var/run/scut-autologin.pid
LOGIN_MODULE=/usr/lib/scut-autologin/login.sh

log() {
	logger -t "$LOGTAG" -s "$1"
}

load_config() {
	config_load "$CFG"
	config_get enabled     main enabled     "0"
	config_get username    main username    ""
	config_get password    main password    ""
	config_get interval    main interval    "30"
	config_get check_host  main check_host  "http://connect.rom.miui.com/generate_204"
	config_get portal_host main portal_host "https://s.scut.edu.cn"
	config_get suffix      main suffix      ""
	config_get ac_ip       main ac_ip       ""
	config_get timeout     main timeout     "5"
}

# ---- connectivity check -----------------------------------------------
# Returns 0 (true) only if we really reached the check host:
#  - HTTP 204 (generate_204 endpoints) -> definitely online;
#  - 2xx whose final URL was NOT bounced onto the portal host -> online.
check_online() {
	local out code url
	out=$(curl -s -o /dev/null -L -m "$timeout" \
		-w '%{http_code}|%{url_effective}' "$check_host" 2>/dev/null) || return 1
	code=${out%%|*}
	url=${out#*|}
	case "$url" in
		"$portal_host"*) return 1 ;;
	esac
	case "$code" in
		204) return 0 ;;
		2*)  return 0 ;;
		*)   return 1 ;;
	esac
}

# ---- portal status ------------------------------------------------------
# echoes: "<result> <ip>"  (result empty if portal unreachable)
get_status() {
	local resp result ip
	resp=$(curl -s -m "$timeout" \
		-H "Referer: $portal_host/" \
		"$portal_host/drcom/chkstatus?callback=dr1002" 2>/dev/null)
	resp=${resp#*(}
	resp=${resp%)*}
	result=$(jsonfilter -s "$resp" -e '@.result' 2>/dev/null)
	ip=$(jsonfilter -s "$resp" -e '@.v46ip' 2>/dev/null)
	echo "${result:-} ${ip:-}"
}

# ---- main loop ----------------------------------------------------------
[ -f "$LOGIN_MODULE" ] || log "login module missing: $LOGIN_MODULE"
. "$LOGIN_MODULE"

echo $$ > "$PIDFILE"

while :; do
	load_config

	if [ "$enabled" != "1" ]; then
		sleep 5
		continue
	fi

	# sanity: interval in seconds, min 5
	case "$interval" in
		''|*[!0-9]*) interval=30 ;;
	esac
	[ "$interval" -lt 5 ] && interval=5

	if check_online; then
		: # online, nothing to do
	else
		log "offline detected, checking portal status"
		status=$(get_status)
		result=${status%% *}
		ip=${status#* }

		if [ "$result" = "1" ]; then
			log "portal reports online but check failed (ip=$ip), maybe transient"
		elif [ -z "$username" ]; then
			log "no credentials configured, cannot login"
		elif [ -z "$ip" ]; then
			log "portal unreachable (no ip yet), retry next cycle"
		else
			log "offline confirmed (ip=$ip), logging in as $username"
			if do_login "$ip"; then
				: # logged in
			else
				log "login did not succeed, retrying next cycle"
			fi
		fi
	fi

	sleep "$interval"
done
