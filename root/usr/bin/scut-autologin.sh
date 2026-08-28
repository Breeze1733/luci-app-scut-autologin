#!/bin/sh
# /usr/bin/scut-autologin.sh
# SCUT campus network auto-login (Dr.COM/ePortal web auth).
#
# Protocol reverse-engineered from the portal page JS (reference/a40.js, a41.js)
# and verified live against s.scut.edu.cn:
#
#   GET {portal}/drcom/chkstatus?callback=drXXXX
#     -> drXXXX({"result":0|1,"v46ip":"x.x.x.x","uid":"..."})
#        result: 0 = offline (need login), 1 = online
#
#   GET {portal}:802/eportal/portal/login (JSONP)
#     callback=drXXXX&login_method=1&user_account=<acct>&user_password=<pass>
#     &wlan_user_ip=<ip>&wlan_user_mac=000000000000&jsVersion=4.1.3
#     &terminal_type=1&lang=zh-cn&mac_type=0
#     -> {"result":1} on success
#
#   IMPORTANT: the wireless portal binds the session to the relay interface
#   MAC. A working login uses  user_account = "<user>@wifi<machex>"  where
#   machex is the MAC (no colons) of the interface holding the default route.
#   When offline the plain account is rejected with msg 512.
#
#   The old kernel endpoint /drcom/login returns 404 on this portal.
#
# Config (UCI /etc/config/scut-autologin):
#   main.{enabled,username,password,interval,check_host,portal_host,suffix,timeout}

. /lib/functions.sh

CFG=scut-autologin
LOGTAG=scut-autologin
PIDFILE=/var/run/scut-autologin.pid

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

# ---- helpers ------------------------------------------------------------

# MAC (no colons, lowercase) of the interface holding the default route
wan_iface_mac() {
	local dev
	dev=$(ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
	[ -n "$dev" ] || return 1
	tr -d ':' < "/sys/class/net/$dev/address" 2>/dev/null | tr 'A-F' 'a-f'
}

# The wireless portal binds the login to "user@wifi<machex>"; honour an
# explicit suffix (e.g. @dx/@lt for ISP plans) if the user configured one.
build_account() {
	local acct="$1"
	if [ -n "$suffix" ]; then
		printf '%s%s' "$acct" "$suffix"
		return
	fi
	local mac
	mac=$(wan_iface_mac)
	if [ -n "$mac" ]; then
		printf '%s@wifi%s' "$acct" "$mac"
	else
		printf '%s' "$acct"
	fi
}

# en_md5 transform from the portal JS: md5(PID+pass+CALG) + CALG + PID
# with PID='1' and CALG='12345678'
md5_password() {
	printf '%s' "1$1""12345678" | md5sum | awk '{print $1 "123456781"}'
}

json_result() {
	local resp=${1#*(}
	resp=${resp%)*}
	jsonfilter -s "$resp" -e '@.result' 2>/dev/null
}

# ---- login --------------------------------------------------------------
do_login() {
	local ip="$1"
	local acct mac wmac
	acct=$(build_account "$username")
	mac=$(wan_iface_mac)
	wmac=$(printf '%s' "$mac" | tr 'a-f' 'A-F')
	[ -n "$wmac" ] || wmac="000000000000"

	local epbase
	case "$portal_host" in
		http://*)  epbase="$portal_host:801" ;;
		*)         epbase="$portal_host:802" ;;
	esac

	local resp ret
	# attempt 1: plaintext password
	resp=$(curl -s -m "$timeout" -G \
		-H "Referer: $portal_host/" \
		-H "User-Agent: Mozilla/5.0" \
		--data-urlencode "callback=dr1002" \
		--data-urlencode "login_method=1" \
		--data-urlencode "user_account=$acct" \
		--data-urlencode "user_password=$password" \
		--data-urlencode "wlan_user_ip=$ip" \
		--data-urlencode "wlan_user_ipv6=" \
		--data-urlencode "wlan_user_mac=$wmac" \
		--data-urlencode "wlan_ac_ip=$ac_ip" \
		--data-urlencode "wlan_ac_name=" \
		--data-urlencode "jsVersion=4.1.3" \
		--data-urlencode "terminal_type=1" \
		--data-urlencode "lang=zh-cn" \
		--data-urlencode "mac_type=0" \
		"$epbase/eportal/portal/login" 2>/dev/null)
	ret=$(json_result "$resp")
	log "login attempt plain (account=$acct, ip=$ip): result=$ret"
	[ "$ret" = "1" ] && { log "login ok"; return 0; }

	# attempt 2: en_md5-transformed password
	local pass2
	pass2=$(md5_password "$password")
	resp=$(curl -s -m "$timeout" -G \
		-H "Referer: $portal_host/" \
		-H "User-Agent: Mozilla/5.0" \
		--data-urlencode "callback=dr1002" \
		--data-urlencode "login_method=1" \
		--data-urlencode "user_account=$acct" \
		--data-urlencode "user_password=$pass2" \
		--data-urlencode "wlan_user_ip=$ip" \
		--data-urlencode "wlan_user_ipv6=" \
		--data-urlencode "wlan_user_mac=$wmac" \
		--data-urlencode "wlan_ac_ip=$ac_ip" \
		--data-urlencode "wlan_ac_name=" \
		--data-urlencode "jsVersion=4.1.3" \
		--data-urlencode "terminal_type=1" \
		--data-urlencode "lang=zh-cn" \
		--data-urlencode "mac_type=0" \
		"$epbase/eportal/portal/login" 2>/dev/null)
	ret=$(json_result "$resp")
	log "login attempt md5: result=$ret"
	[ "$ret" = "1" ] && { log "login ok (md5 password)"; return 0; }

	log "login failed: $(printf '%s' "$resp" | cut -c1-160)"
	return 1
}

# ---- main loop ----------------------------------------------------------
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
