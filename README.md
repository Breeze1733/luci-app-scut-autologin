# luci-app-scut-autologin

华南理工大学校园网自动登录插件，适用于使用 ImmortalWrt 进行无线中继的
路由器。插件通过 LuCI 配置 Dr.COM/ePortal Web 认证信息，在认证过期或掉线
后自动重新登录。

## 功能

- 定时检测外网连通性，并识别认证网关的重定向
- 掉线后自动查询门户状态并执行登录
- 支持校园用户、电信、联通和移动账号后缀
- LuCI 页面显示认证状态和当前 IP，每 10 秒刷新
- 使用 procd 守护进程，支持开机启动和异常拉起

## 工作方式

守护进程 `/usr/bin/scut-autologin.sh` 默认每 30 秒执行一次检测：

1. 请求 `check_host`，仅当返回 HTTP 204 或其他 2xx 且最终 URL 未跳转到
   `portal_host` 时判定为已联网。
2. 未联网时请求 `/drcom/chkstatus`，读取门户返回的在线状态和本机 IP。
3. 确认离线后调用登录模块 `/usr/lib/scut-autologin/login.sh`，请求
   `:802/eportal/portal/login`（HTTP 认证服务器使用 `:801`）。
4. 登录先尝试明文密码，失败后再尝试门户使用的 `en_md5` 格式。

无线中继场景下，未配置运营商后缀时，脚本会读取默认路由接口的 MAC 地址，
将账号组装为 `<账号>@wifi<小写 MAC（去掉冒号）>`。配置了后缀后则直接追加
该后缀，例如 `<账号>@dx`。

## 要求

- ImmortalWrt/OpenWrt，且使用支持 Lua 的 LuCI
- `curl`
- `jsonfilter`
- 可访问华南理工大学认证门户

`curl` 和 `jsonfilter` 通常已经包含在固件中。缺少时可在路由器上安装：

```sh
opkg update
opkg install curl jsonfilter
```

## 编译安装

将仓库目录放入 ImmortalWrt 源码树的 `feeds/luci/applications/`：

```sh
cp -r /path/to/luci-app-scut-autologin feeds/luci/applications/
./scripts/feeds update luci
./scripts/feeds install -a -p luci
make menuconfig
```

在 `LuCI -> Applications` 中选择 `luci-app-scut-autologin`（建议编译为 `<M>`），
然后编译：

```sh
make package/feeds/luci/luci-app-scut-autologin/compile V=s
```

生成的 ipk 通常位于 `bin/packages/<架构>/`。将其上传到路由器后安装并启动：

```sh
opkg install luci-app-scut-autologin_*.ipk
在 `LuCI -> Applications` 中选择 `luci-app-scut-autologin`（建议编译为 `<M>`），
/etc/init.d/scut-autologin start
```

安装后进入 `服务 -> 校园网自动登录`，填写账号和密码，勾选启用并点击保存应用。
服务会在下一个检测周期重新读取配置，无需重启。

## 配置

配置文件：`/etc/config/scut-autologin`

| 选项 | 说明 | 默认值 |
| --- | --- | --- |
| `enabled` | 是否启用，`1` 启用，`0` 停用 | `0` |
| `username` | 校园网账号（学号或工号） | 空 |
| `password` | 校园网密码 | 空 |
| `interval` | 检测间隔，最小 5 秒 | `30` |
| `check_host` | 连通性检测 URL，建议使用 204 接口 | `http://connect.rom.miui.com/generate_204` |
| `portal_host` | 认证门户主机地址，不带路径 | `https://s.scut.edu.cn` |
| `suffix` | 账号后缀：空、`@dx`、`@lt` 或 `@yd` | 空 |
| `timeout` | HTTP 请求超时时间，1 至 60 秒 | `5` |

也可以直接编辑 UCI 配置：

```sh
uci set scut-autologin.main.enabled='1'
uci set scut-autologin.main.username='你的账号'
uci set scut-autologin.main.password='你的密码'
uci commit scut-autologin
```

## 查看状态与日志

```sh
# 查看服务状态
/etc/init.d/scut-autologin status

# 查看插件日志
logread -e scut-autologin

# 直接检查认证门户
curl -s 'https://s.scut.edu.cn/drcom/chkstatus?callback=dr1002'
```

脚本是持续运行的守护进程，不建议手动重复启动。需要临时停止时使用：

```sh
/etc/init.d/scut-autologin stop
```

## 注意事项

- 密码以明文保存在 `/etc/config/scut-autologin`，请限制路由器管理权限。
- 插件只负责 Web 认证，不负责 802.1X、宽带拨号或上游 Wi-Fi 关联。
- `portal_host` 默认值针对当前校园门户；如果学校门户地址或协议发生变化，
  需要同步调整该配置和登录协议。
- 运营商后缀由门户规则决定。移动用户应先确认门户实际要求的后缀，再选择
  `@yd` 或手动修改配置。
- 不同校区、网络出口或门户版本可能要求不同的账号格式，登录失败时请先查看
  日志，并确认默认路由接口的 MAC 地址和门户地址正确。

## 许可证

本项目采用 [MIT License](https://opensource.org/license/mit/)。
