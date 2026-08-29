#!/bin/sh
# /usr/lib/scut-autologin/login.sh
# Login routine for the SCUT campus network auto-login daemon.
# Sourced by /usr/bin/scut-autologin.sh (detection/keep-alive lives there);
# this file only performs the actual portal login.
#
# Protocol verified against a captured successful browser login (HAR, 2026-08):
#
#   GET {portal}:802/eportal/portal/login (JSONP)
#     callback=drXXXX&login_method=1&user_account=<user>&user_password=<pass>
#     &wlan_user_ip=<ip>&wlan_user_ipv6=&wlan_user_mac=000000000000
#     &wlan_ac_ip=<ac>&wlan_ac_name=&jsVersion=4.1.3
#     &terminal_type=1&lang=zh-cn&mac_type=0
#     -> {"result":1,"msg":"Portal协议认证成功！"}
#
#   Portal config (page/loadConfig) for SCUT: login_method=1, en_md5=0,
#   account_suffix=""  ->  plain account, plain password, no MAC suffix.
#   The client MAC is bound server-side (chkstatus "olmac"); the AC address
#   comes from the captive-portal redirect URL (?wlanacip=x.x.x.x) and is
#   auto-detected below (empty wlan_ac_ip makes Radius time out, ret_code 8).
#
#   The old kernel endpoint /drcom/login returns 404 on this portal.
#
# Expects from the caller (daemon's load_config or CLI flags): the globals
#   portal_host timeout username password ac_ip check_host
# and the logging wrapper log().

json_result() {
	local resp=${1#*(}
	resp=${resp%)*}
	jsonfilter -s "$resp" -e '@.result' 2>/dev/null
}

# AC address for wlan_ac_ip: when offline, any HTTP request is redirected
# by the AC to {portal}/a79.htm?wlanacip=x.x.x.x - grab it from the final URL.
detect_ac_ip() {
	local url
	url=$(curl -s -o /dev/null -L -m "$timeout" \
		-w '%{url_effective}' "${check_host:-http://connect.rom.miui.com/generate_204}" 2>/dev/null)
	printf '%s' "$url" | sed -n 's/.*[?&]wlanacip=\([0-9.]*\).*/\1/p'
}

# ---- login --------------------------------------------------------------
do_login() {
	local ip="$1"
	[ -n "$ac_ip" ] || ac_ip=$(detect_ac_ip)
	[ -n "$ac_ip" ] || log "warning: AC address not detected, login may fail (ret_code 8)"

	local epbase
	case "$portal_host" in
		http://*)  epbase="$portal_host:801" ;;
		*)         epbase="$portal_host:802" ;;
	esac

	local resp ret
	resp=$(curl -s -m "$timeout" -G \
		-H "Referer: $portal_host/" \
		-H "User-Agent: Mozilla/5.0" \
		--data-urlencode "callback=dr1002" \
		--data-urlencode "login_method=1" \
		--data-urlencode "user_account=$username" \
		--data-urlencode "user_password=$password" \
		--data-urlencode "wlan_user_ip=$ip" \
		--data-urlencode "wlan_user_ipv6=" \
		--data-urlencode "wlan_user_mac=000000000000" \
		--data-urlencode "wlan_ac_ip=$ac_ip" \
		--data-urlencode "wlan_ac_name=" \
		--data-urlencode "jsVersion=4.1.3" \
		--data-urlencode "terminal_type=1" \
		--data-urlencode "lang=zh-cn" \
		--data-urlencode "mac_type=0" \
		"$epbase/eportal/portal/login" 2>/dev/null)
	ret=$(json_result "$resp")
	log "login attempt (account=$username, ip=$ip, ac=$ac_ip): result=$ret"
	[ "$ret" = "1" ] && { log "login ok"; return 0; }

	log "login failed: $(printf '%s' "$resp" | cut -c1-160)"
	return 1
}

# ---- standalone test mode (direct execution only) ------------------------
if [ "${0##*/}" = "login.sh" ]; then
	# fallback logger so the file works without the daemon
	log() {
		if command -v logger >/dev/null 2>&1; then
			logger -t scut-autologin -s "$1"
		else
			echo "scut-autologin: $1" >&2
		fi
	}

	if [ "$#" -gt 0 ]; then
		while getopts "u:p:i:h:t:" opt; do
			case "$opt" in
				u) username=$OPTARG ;;
				p) password=$OPTARG ;;
				i) force_ip=$OPTARG ;;
				h) portal_host=$OPTARG ;;
				t) timeout=$OPTARG ;;
				*) echo "usage: $0 -u <user> -p <pass> [-i <ip>] [-h <portal>] [-t <sec>]" >&2; exit 2 ;;
			esac
		done

		# UCI fills whatever the command line left empty
		if [ -f /etc/config/scut-autologin ]; then
			. /lib/functions.sh
			config_load scut-autologin
			config_get u main username    "";  : "${username:=$u}"
			config_get u main password    "";  : "${password:=$u}"
			config_get u main portal_host "";  : "${portal_host:=$u}"
			config_get u main ac_ip       "";  : "${ac_ip:=$u}"
			config_get u main timeout     "";  : "${timeout:=$u}"
			config_get u main check_host  "";  : "${check_host:=$u}"
		fi
		: "${portal_host:=https://s.scut.edu.cn}"
		: "${timeout:=5}"

		[ -n "$username" ] || { echo "error: -u <user> required" >&2; exit 2; }
		[ -n "$password" ] || { echo "error: -p <pass> required" >&2; exit 2; }

		# local IP as seen by the portal (auto unless -i)
		ip=${force_ip:-}
		if [ -z "$ip" ]; then
			resp=$(curl -s -m "$timeout" -H "Referer: $portal_host/" \
				"$portal_host/drcom/chkstatus?callback=dr1002" 2>/dev/null)
			ip=$(jsonfilter -s "${resp#*(}" -e '@.v46ip' 2>/dev/null)
		fi
		[ -n "$ip" ] || { echo "error: could not determine local IP, pass one with -i" >&2; exit 1; }

		log "test login (account=$username, ip=$ip)"
		do_login "$ip" && exit 0 || exit 1
	fi
fi
