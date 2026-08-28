# luci-app-scut-autologin

华南理工大学校园网（Dr.COM/ePortal Web 认证）自动登录插件，适用于
ImmortalWrt 无线中继场景：路由器通过中继上游 Wi-Fi 上网，掉线（认证过期、
被踢下线）后自动重新认证。

## 工作原理

后台守护进程 `/usr/bin/scut-autologin.sh` 每隔 N 秒（默认 30s）请求一次
检测地址（默认小米的 `generate_204` 探测接口）：

- 返回 HTTP 204，且最终 URL 没有被劫持跳到认证服务器 → 已联网；
- 被重定向到认证页 / 超时 → 未认证，请求认证服务器 `/drcom/chkstatus`
  读取本机 IP 和在线状态，然后向 `/drcom/login` 带账号密码发起 JSONP
  GET 登录，失败会重试一次。

> 关键点：不能用"有 HTTP 响应就算联网"来判断——未认证时任何 HTTP 请求
> 都会被网关 302 到认证页并返回 200，所以脚本同时校验 `url_effective`
> 是否落在 `portal_host` 上。

协议是从认证页前端 JS（`reference/a40.js`、`reference/a41.js`）逆向的：

```
GET  {portal}/drcom/chkstatus?callback=dr1002
  -> jsonp: dr1002({"result":0,"v46ip":"10.195.50.53","ss4":"...",...})
     result: 0 = 离线, 1 = 在线; v46ip = 本机 IP

GET  {portal}/drcom/login?DDDDD=<账号>&upass=<密码>&0MKKey=123456
     &R1=&R2=&R3=2&R6=0&para=00&v6ip=&callback=dr1002
  -> jsonp: {"result":1} 表示成功
```

配置存于 `/etc/config/scut-autologin`，守护进程每个周期重新读取，LuCI
点"保存并应用"后下个周期即生效，无需重启服务。

## LuCI 页面

菜单位置：`服务 → 校园网自动登录`

- 启用开关
- 账号 / 密码
- 检测间隔（秒）
- 检测地址 / 认证服务器 / 运营商（R3）/ 请求超时（高级）
- 当前状态：实时显示"已联网（IP）/ 未认证 / 无法访问认证服务器"，10s 自动刷新

## 安装

把整个 `luci-app-scut-autologin` 目录放进 ImmortalWrt 源码树的
`feeds/luci/applications/`（旧版 Lua LuCI）：

```sh
# 在 buildroot 根目录
cp -r /path/to/luci-app-scut-autologin feeds/luci/applications/
./scripts/feeds update luci   # 仅当之前没装过 luci feed
./scripts/feeds install -a -p luci   # 可选
make menuconfig  # LuCI -> Applications -> luci-app-scut-autologin 选 <M>
make package/feeds/luci/luci-app-scut-autologin/compile V=s
```

生成的 ipk 在 `bin/packages/<arch>/`，传到路由器：

```sh
opkg install luci-app-scut-autologin_*.ipk
/etc/init.d/scut-autologin enable
/etc/init.d/scut-autologin start
```

依赖：`curl`、`jsonfilter`（固件一般自带；没有则 `opkg install curl`）。

## 配置项（/etc/config/scut-autologin）

| 项 | 说明 | 默认 |
|---|---|---|
| `enabled` | 1 启用 / 0 停用 | 0 |
| `username` | 认证账号 | 空 |
| `password` | 认证密码 | 空 |
| `interval` | 检测间隔（秒），最小 5 | 30 |
| `check_host` | 连通性检测 URL（推荐 204 接口） | `http://connect.rom.miui.com/generate_204` |
| `portal_host` | 认证服务器地址 | `https://s.scut.edu.cn` |
| `suffix` | 运营商账号后缀：空=校园用户，`@dx`=电信，`@lt`=联通 | 空 |
| `timeout` | HTTP 超时（秒） | 5 |

## 手动调试

```sh
# 看日志
logread | grep scut-autologin

# 手动跑一次检测+登录（前台）
/usr/bin/scut-autologin.sh &   # 注意脚本是死循环，用 kill 结束

# 直接测认证服务器是否可达
curl -s 'https://s.scut.edu.cn/drcom/chkstatus?callback=dr1002'
```

## 注意事项

- 认证服务器域名是固定的；URL 里 `wlanacip=172.18.50.11` 是 AC 参数，
  不需要配置。
- 运营商不是通过 R3 参数，而是账号后缀：认证页配置（a79.htm 的
  `carrier` 字段）为 校园用户=`""`、电信=`@dx`、联通=`@lt`。插件把
  后缀直接拼在账号后面发送，LuCI 页面上选择即可。若你办理的是移动，
  先抓包确认后缀再填。
- 密码明文存 UCI（`/etc/config/scut-autologin`），与其他校园网插件一致。
- 本插件只处理 Web 认证，不影响 802.1X 客户端认证。
