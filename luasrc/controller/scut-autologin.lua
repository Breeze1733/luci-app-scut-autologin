-- Copyright 2026 XiaoHe
-- Licensed to the public under the MIT License.

module("luci.controller.scut-autologin", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/scut-autologin") then
		return
	end

	entry({"admin", "services", "scut-autologin"},
		cbi("scut-autologin"), _("SCUT 校园网自动登录"), 60).dependent = true

	-- status endpoint: LuCI page polls this to show online state
	entry({"admin", "services", "scut-autologin", "status"},
		call("action_status")).leaf = true
end

function action_status()
	local uci = require "luci.model.uci".cursor()
	local portal = uci:get("scut-autologin", "main", "portal_host") or ""
	local timeout = uci:get("scut-autologin", "main", "timeout") or "5"
	local http = require "luci.http"

	local result, ip = "-1", ""
	local out = luci.sys.exec(string.format(
		"curl -s -m %s '%s/drcom/chkstatus?callback=dr1002' 2>/dev/null",
		timeout, portal))

	local body = out:match("%((.*)%)")
	if body then
		result = body:match('"result":%s*(%-?%d+)') or "-1"
		ip = body:match('"v46ip":%s*"([^"]*)"') or ""
	end

	http.prepare_content("application/json")
	http.write(string.format('{"result":%s,"ip":"%s"}', result, ip))
end
