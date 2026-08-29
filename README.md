# luci-app-scut-autologin

华南理工大学校园网自动登录插件，适用于使用 ImmortalWrt 进行无线中继的路由器。插件通过 LuCI 配置 Dr.COM/ePortal Web 认证信息，在认证过期或掉线后自动重新登录。

## 功能特性

- 定时检测外网连通性，并识别认证网关的重定向
- 掉线后自动查询门户状态并执行登录
- LuCI 页面显示认证状态和当前 IP，每 10 秒刷新
- 使用 procd 守护进程，支持开机启动和异常拉起
- 配置修改后无需重启服务，下一个检测周期自动生效

## 工作原理

守护进程 `/usr/bin/scut-autologin.sh` 默认每 30 秒（可配置）执行一次检测：

1. 请求 `check_host`，仅当返回 HTTP 204 或其他 2xx 且最终 URL 未跳转到 `portal_host` 时判定为已联网。
2. 未联网时请求 `/drcom/chkstatus`，读取门户返回的在线状态和本机 IP。
3. 确认离线后调用登录模块 `/usr/lib/scut-autologin/login.sh`，请求 `:802/eportal/portal/login`。AC 地址自动从门户重定向中检测（也可在配置中手动指定 `ac_ip`）。
4. 登录使用明文密码（当前门户配置 `en_md5=0`，无需密码变换）。

账号原样传给门户，不做任何拼接。客户端 MAC 由门户在服务端绑定（`chkstatus` 返回的 `olmac` 字段）。如果门户要求运营商后缀（如电信 `@dx`、移动 `@yd`），直接在账号一栏填写完整账号即可，例如 `20230000@dx`。

## 环境要求

- ImmortalWrt / OpenWrt，且使用支持 Lua 的 LuCI
- `curl`、`jsonfilter`（通常已包含在固件中，缺少时执行 `opkg update && opkg install curl jsonfilter`）
- 可访问华南理工大学认证门户

## 安装

### 方式一：编译为 IPK（推荐）

1. 将仓库目录放入 ImmortalWrt 源码树的 `feeds/luci/applications/`：

   ```sh
   cp -r /path/to/luci-app-scut-autologin feeds/luci/applications/
   ./scripts/feeds update luci
   ./scripts/feeds install -a -p luci
   make menuconfig
   ```

2. 在 `LuCI -> Applications` 中选择 `luci-app-scut-autologin`（建议编译为 `<M>`），然后编译：

   ```sh
   make package/feeds/luci/luci-app-scut-autologin/compile V=s
   ```

3. 生成的 ipk 位于 `bin/packages/<架构>/`，上传到路由器后安装并启动：

   ```sh
   opkg install luci-app-scut-autologin_*.ipk
   /etc/init.d/scut-autologin enable
   /etc/init.d/scut-autologin start
   ```

### 方式二：直接复制文件

适合个人使用或快速验证，无需编译环境。将仓库中的文件按对应关系复制到路由器：

| 仓库路径 | 路由器路径 |
| --- | --- |
| `luasrc/controller/scut-autologin.lua` | `/usr/lib/lua/luci/controller/scut-autologin.lua` |
| `luasrc/model/cbi/scut-autologin.lua` | `/usr/lib/lua/luci/model/cbi/scut-autologin.lua` |
| `root/` 下的所有文件 | 同名路径（整体镜像到 `/`） |

例如在本地通过 scp 推送（IP 按实际修改）：

```sh
scp luasrc/controller/scut-autologin.lua root@192.168.1.1:/usr/lib/lua/luci/controller/
scp luasrc/model/cbi/scut-autologin.lua     root@192.168.1.1:/usr/lib/lua/luci/model/cbi/
scp -r root/. root@192.168.1.1:/
```

然后在路由器上收尾：

```sh
chmod +x /etc/init.d/scut-autologin /usr/bin/scut-autologin.sh /usr/lib/scut-autologin/login.sh
rm -rf /tmp/luci-indexcache*        # 清除 LuCI 索引缓存，否则新页面不出现
/etc/init.d/scut-autologin enable
/etc/init.d/scut-autologin start
```

> 注意：如果路由器上已有配置文件 `/etc/config/scut-autologin`（存有账号密码），复制时不要覆盖它。

## 使用

安装完成后进入 `服务 -> 校园网自动登录`，填写账号和密码，勾选启用并点击保存应用。服务会在下一个检测周期重新读取配置，无需重启。

也可以直接通过 UCI 配置：

```sh
uci set scut-autologin.main.enabled='1'
uci set scut-autologin.main.username='你的账号'
uci set scut-autologin.main.password='你的密码'
uci commit scut-autologin
```

## 配置项

配置文件：`/etc/config/scut-autologin`

| 选项 | 说明 | 默认值 |
| --- | --- | --- |
| `enabled` | 是否启用，`1` 启用，`0` 停用 | `0` |
| `username` | 校园网账号（学号或工号），需要运营商后缀时填写完整账号 | 空 |
| `password` | 校园网密码 | 空 |
| `interval` | 检测间隔（秒），小于 5 按 5 处理 | `30` |
| `check_host` | 连通性检测 URL，建议使用 204 接口 | `http://connect.rom.miui.com/generate_204` |
| `portal_host` | 认证门户主机地址，不带路径 | `https://s.scut.edu.cn` |
| `ac_ip` | 认证控制器 IP；留空则登录前自动检测 | 自动检测 |
| `timeout` | HTTP 请求超时时间，1 至 60 秒 | `5` |

## 状态与日志

```sh
# 查看服务状态
/etc/init.d/scut-autologin status

# 查看插件日志
logread -e scut-autologin

# 直接检查认证门户
curl -s 'https://s.scut.edu.cn/drcom/chkstatus?callback=dr1002'
```

登录模块支持独立运行，便于手动排查问题：

```sh
/usr/lib/scut-autologin/login.sh -u <账号> -p <密码> [-i <本机IP>] [-h <门户地址>] [-t <超时秒>]
```

不传 `-i` 时会自动从门户获取本机 IP；账号、密码等留空的参数会回退读取 UCI 配置。

脚本是持续运行的守护进程，不建议手动重复启动。需要临时停止时使用：

```sh
/etc/init.d/scut-autologin stop
```

## 注意事项

- 密码以明文保存在 `/etc/config/scut-autologin`，请限制路由器管理权限。
- 插件只负责 Web 认证，不负责 802.1X、宽带拨号或上游 Wi-Fi 关联。
- `portal_host` 默认值针对当前校园门户；如果学校门户地址或协议发生变化，需要同步调整该配置和登录协议。
- 运营商后缀由门户规则决定。移动用户应先确认门户实际要求的后缀，再填写完整账号。
- 不同校区、网络出口或门户版本可能要求不同的账号格式，登录失败时请先查看日志，并确认门户地址正确。

## 许可证

本项目采用 [MIT License](https://opensource.org/license/mit/)。
