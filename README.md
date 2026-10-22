# 外设电量 · PeripheralBattery

一个轻量的 macOS 菜单栏工具，用于查看 ROG 键盘和雷蛇鼠标的电量。使用原生 Objective-C、AppKit 和 IOKit，无第三方运行时依赖。

## 功能

- 菜单栏仅显示键盘图标，点击查看两个设备的电量。
- 原生半透明菜单、大图标、细电量条；低电量（≤20%）显示橙色。
- 支持键盘充电状态，百分比旁显示闪电。
- 每小时自动刷新，启动、系统唤醒和手动操作时也会查询。
- 点击“立即刷新”保持菜单打开；支持登录自动启动。
- 不联网、不记录输入或电量历史，无额外常驻服务。

## 支持设备

| 设备 | 接收器 VID:PID | 支持内容 |
| --- | --- | --- |
| ROG Falchion RX Low Profile，经 OMNI 接收器 | `0B05:1ACE` | 电量、充电状态 |
| Razer Viper V3 HyperSpeed | `1532:00B8` | 电量 |

目前仅适配上述 2.4 GHz 接收器。其他型号、蓝牙和有线模式未验证。设备睡眠、断连或查询失败时显示 `—`，不沿用旧读数。电量来自设备固件估计。

## 构建与运行

需要 macOS 13 或更新版本及 Apple Command Line Tools（`xcode-select --install`），构建当前机器架构的应用。

```sh
git clone https://github.com/fandiyi047/PeripheralBattery.git
cd PeripheralBattery
bash script/build_and_run.sh --build
./PeripheralBattery.app/Contents/MacOS/PeripheralBattery --self-test
open PeripheralBattery.app
```

首次读取鼠标可能需要在 **系统设置 → 隐私与安全性 → 输入监控** 中允许 PeripheralBattery，然后退出并重新打开应用。

按需查询一次后退出：

```sh
./PeripheralBattery.app/Contents/MacOS/PeripheralBattery --once
```

## 更新与权限

默认使用临时签名（ad-hoc），适合试用，但重新构建后 macOS 可能要求重新授权输入监控。

长期使用时，请使用自己钥匙串中的固定代码签名证书，并在每次构建时复用同一身份：

```sh
CODE_SIGN_IDENTITY='你的代码签名证书名称或 SHA-1' bash script/build_and_run.sh --build
```

可通过 `CODE_SIGN_KEYCHAIN` 指定已解锁的钥匙串。脚本不会创建证书、修改系统信任或读取密码。指定身份签名失败时构建会停止，不会悄悄降级为临时签名。

保留同一签名证书、bundle ID 和安装路径有助于维持更新前后的权限；从临时签名迁移到固定证书时需要重新授权。仓库不含作者的本地签名证书、私钥、密码或已签名二进制，也未提供 Apple 公证版本。

## 登录自动启动

构建成功后执行：

```sh
bash script/install_autostart.sh
```

安装到 `~/Applications/PeripheralBattery.app`，使用用户 LaunchAgent 在登录时启动。手动退出后不会反复重启。更新时重复构建和安装，并保持原签名身份。

关闭自动启动：

```sh
launchctl bootout "gui/$(id -u)/local.fy.PeripheralBattery"
launchctl disable "gui/$(id -u)/local.fy.PeripheralBattery"
```

## 资源与实现

应用仅一个进程，后台队列查询 HID，结束后关闭设备连接。每小时定时器允许 30 秒合并唤醒容差，不持续轮询输入。开发机曾测得 physical footprint 约 17–25 MB；系统版本、菜单使用和字体缓存会影响结果，RSS 与 physical footprint 口径不同。

源码位于 `src/main.m`。`--self-test` 验证回复解析、边界电量、错误长度、校验和、事务 ID 及充电状态。实际硬件兼容性仍需连接设备验证。

## 协议来源与许可

本项目使用 **GPL-3.0-or-later**，见 [LICENSE](LICENSE)。

- [FerrisPulse / RazerDeviceHelper.cs](https://github.com/Ferris-echo/FerrisPulse/blob/main/src/Hardware/RazerDeviceHelper.cs)：雷蛇电量协议参考。
- [G-Helper / AsusKeyboard.cs](https://github.com/seerge/g-helper/blob/main/app/Peripherals/Keyboard/AsusKeyboard.cs)：ASUS 电源查询。
- [G-Helper / Falchion.cs](https://github.com/seerge/g-helper/blob/main/app/Peripherals/Keyboard/Models/Falchion.cs)：Falchion 电量位置及 OMNI 报文。
- [EZ2.4G](https://github.com/Ap0LoG1zE/EZ2.4G)、[2.4G-battery-viewer](https://github.com/yszyszysz233/2.4G-battery-viewer)：项目调研参考。

不包含 DPI、灯效、按键映射、固件升级或配对设置功能。
