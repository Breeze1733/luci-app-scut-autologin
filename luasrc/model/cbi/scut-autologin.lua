-- Copyright 2026 XiaoHe
-- Licensed to the public under the MIT License.

local m, s, o
local uci = require "luci.model.uci".cursor()

m = Map("scut-autologin", translate("校园网自动登录"),
	translate("校园网无线中继下的自动认证（Dr.COM/ePortal）。" ..
		"按设定间隔检测连通性，掉线时自动重新登录。"))

s = m:section(NamedSection, "main", "main", translate("基本设置"))
s.addremove = false
s.anonymous = true

-- 启用开关
o = s:option(Flag, "enabled", translate("启用自动登录"))
o.rmempty = false
o.default = "0"
o.description = translate("开启后将按下方间隔定时检测连通性，未连通则自动登录校园网。")

-- 账号
o = s:option(Value, "username", translate("账号"))
o.rmempty = false
o.description = translate("校园网认证账号（学号或工号）。")

-- 密码
o = s:option(Value, "password", translate("密码"))
o.rmempty = false
o.password = true
o.description = translate("校园网认证密码。")

-- 检测间隔
o = s:option(Value, "interval", translate("检测间隔（秒）"))
o.rmempty = false
o.datatype = "and(uinteger,min(5))"
o.default = "30"
o.description = translate("每隔多少秒检测一次连通性，小于 5 秒按 5 秒处理。")

-- 检测目标
o = s:option(Value, "check_host", translate("检测地址"))
o.rmempty = false
o.default = "http://connect.rom.miui.com/generate_204"
o.description = translate("用于判断是否连通的网址。推荐 generate_204 类接口：返回 HTTP 204 且没有被重定向到认证页才算联网。")

-- 认证服务器
o = s:option(Value, "portal_host", translate("认证服务器"))
o.rmempty = false
o.default = "https://s.scut.edu.cn"
o.description = translate("校园网认证页地址（仅主机部分，不带路径）。一般是固定的 https://s.scut.edu.cn，无需修改。")

-- 账号后缀（运营商）
o = s:option(ListValue, "suffix", translate("运营商"))
o:value("", translate("校园用户（默认）"))
o:value("@dx", translate("校园电信"))
o:value("@lt", translate("校园联通"))
o:value("@yd", translate("校园移动"))
o.default = ""
o.rmempty = true

-- 超时
o = s:option(Value, "timeout", translate("请求超时（秒）"))
o.rmempty = false
o.datatype = "and(uinteger,min(1),max(60))"
o.default = "5"
o.description = translate("检测与登录请求的 HTTP 超时时间。")

-- 状态显示区（AJAX 轮询 controller 的 status 端点）
local status = s:option(DummyValue, "_status", translate("当前状态"))
status.rawhtml = true
function status.cfgvalue()
	return string.format([[
<div id="scut-status" style="padding:4px 0">正在获取…</div>
<script type="text/javascript">
(function() {
	var url = '%s';
	function refresh() {
		XHR.get(url, null, function(x, data) {
			var el = document.getElementById('scut-status');
			if (!el || !data) return;
			if (data.result == 1) {
				el.innerHTML = '<span style="color:green">✔ 已联网</span>（IP: ' +
					((data.ip && data.ip != '0.0.0.0') ? data.ip : '未知') + '）';
			} else if (data.result == 0) {
				el.innerHTML = '<span style="color:red">✘ 未认证 / 已掉线</span>';
			} else {
				el.innerHTML = '<span style="color:orange">? 无法访问认证服务器</span>';
			}
		});
	}
	refresh();
	setInterval(refresh, 10000);
})();
</script>]],
		luci.dispatcher.build_url("admin/services/scut-autologin/status"))
end

return m
