#
# Copyright (C) 2026 XiaoHe
# SPDX-License-Identifier: MIT
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-scut-autologin
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=XiaoHe

LUCI_TITLE:=LuCI app for SCUT campus network auto login (wireless relay)
LUCI_DESCRIPTION:=Periodically pings the Internet and automatically re-authenticates \
	against the SCUT campus network portal (Dr.COM/ePortal) when offline. \
	Suitable for ImmortalWrt wireless relay setups.
LUCI_DEPENDS:=+luci
LUCI_PKGARCH:=all

# 约定本目录放在 luci 仓库的 applications/ 下（feeds/luci/applications/）。
# 若放在独立的 package/ 目录中，请改为：
#   include $(TOPDIR)/feeds/luci/luci.mk
include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
