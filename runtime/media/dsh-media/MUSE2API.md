# muse2api 接入与安卓构建

[English](MUSE2API.en.md)

本分支在原有 MIT 许可的 dsh-media 上增加 Muse 图片与视频协议。App 继续使用原有聊天生成模式、图片卡片、视频播放和保存能力。Muse 网关需要单独运行；不会把 Muse 账号或服务端登录态打包进 APK。

## 从 GitHub 构建

在自己的 dsh-go fork 中应用本次改动，启用 Actions，在 **Android + Muse → Run workflow** 运行。使用 Ubuntu 24.04，Flutter 3.47.7、Node 24.22.1、JDK 17、Gradle 9.3.1；App 的 SDK/NDK 版本读取 Flutter 的配置，原生启动组件另使用 `runtime/tawcroot/source.json` 固定的 NDK。工作流按顺序检查插件与 App、构建 arm64 运行时、调用仓库的 `tooling/build-apk.sh`、校验 APK 签名，然后上传两个 artifact：

- `dsh-go-muse-arm64`：Android 8.0 以上 arm64 真机的 APK、SHA256SUMS。
- `muse-media-plugin`：`ccch1mneyyy-dsh-media-0.3.1-muse.1.tgz`、说明、SHA256SUMS。

构建工具来自 [subosito/flutter-action](https://github.com/subosito/flutter-action)、[android-actions/setup-android](https://github.com/android-actions/setup-android)、[actions/setup-java](https://github.com/actions/setup-java)、[gradle/actions](https://github.com/gradle/actions)。仓库原来已有运行时构建，本工作流把检查、APK 与产物下载接在一起，不自动发布 Release。

默认使用 Android 调试证书签名，APK 可安装，但不能覆盖官方不同证书的安装；GitHub 临时 runner 的证书也不保证跨次相同。已有安装先导出资料；长期自用请按原项目文档配置自己的稳定签名。这里没有使用官方发布密钥。

## 安装修改后的媒体插件

**APK 与插件都需要。** APK 包含 App 和 Linux 运行时；定制媒体插件作为独立 tgz 提供，仍通过原来的插件安装机制加载。它不会自动替换手机上已经安装的市场版本。

将 tgz 放到手机内核/远程主机可读的绝对路径，在该主机的终端运行：

```sh
dsh plugin --profile web add /绝对路径/ccch1mneyyy-dsh-media-0.3.1-muse.1.tgz
```

本包保留原包名，文件安装用于替换同名插件。安装前记录原服务设置；按安装提示重启主机/内核，在插件页确认当前包来自本地 tgz、版本为 `0.3.1-muse.1`。远程主机也要在远程主机安装插件，不能只改手机。

## 手机设置

在“图像与视频”的添加服务列表中选择 **muse2api · 图片** 与 **muse2api · 视频**，分别设置并启用：

| 项目 | 图片 | 视频 |
|---|---|---|
| 协议 | `muse-image` | `muse-video` |
| 模型 | `muse-image` | `muse-video` |
| API 根地址 | `http://服务器IP:18610/v1` | 相同地址 |
| 密钥 | muse2api 配置的 `MUSE2API_KEY` | 同一凭据可共用 |

预设里的 `127.0.0.1` 是占位地址；网关在电脑/服务器上时，必须改成手机/主机实际能访问的 IP 或域名。不要填 `/admin`。服务器根地址会自动补 `/v1`，已有 `/v1` 不会重复追加。反代前缀如 `https://example.com/muse/v1` 也会保留。HTTP 会明文传输密钥与内容；有域名时可使用 HTTPS。

设置好每类默认服务和模型，在聊天中选图片或视频生成模式，然后输入例如“生成一张竖版橘猫海报”或“生成一段 5 秒的日落海面视频”。也可让当前聊天模型调用 `generate_image`、`edit_image`、`generate_video`。**聊天模型需支持工具调用**；muse2api 的 `muse-spark` 不能假定支持原生工具调用，媒体接入不要求替换原来的 DeepSeek 等聊天模型。

## 运行方式与边界

- 图片使用 `POST /v1/images/tasks`，编辑参考图通过 JSON `images: [{url: dataURL}]` 传入；视频使用 `POST /v1/videos`。均只提交一次，后续 GET 查询，不会因为提交响应丢失而自动重发。
- 图片和视频均返回后台 job，完成后由 `get_media_result` 展示聊天卡片。已知任务在 Host 重启后可用原会话的 `resume_media(rid)` 续查；尚未拿到任务 ID 的断线无法可靠恢复。
- 原图/视频先保存为主机工作区文件，沿用 App 的媒体协议；服务器同源下载携带 Bearer，第三方 CDN 不携带该密钥。仅显式配置的 Muse 来源可用 HTTP/局域网；其他供应商保留原有公共 HTTPS 限制。视频重定向仍按原下载器拒绝处理。
- 一次一张图，最多一张 PNG/JPEG/WebP 参考图（10 MB），不是 Muse 服务端最大参考图数。图片比例为 1:1、16:9、9:16、4:3、3:4；视频提供 16:9/9:16 与 5/6/8/10 秒请求选项。实际输出由 Muse 决定。
- Muse 没有公开的取消接口。停止本地 job 不代表服务端已取消；状态展示不编造百分比。沿用原插件的费用审批与本地预算，预留不是 Muse 报价，可在设置中调整。

## 验证

```sh
cd runtime/media/dsh-media
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

新增 `test/muse.test.js` 用本地 HTTP 服务验证异步提交、图片编辑请求、状态查询、鉴权下载、断线不重发和来源隔离；Linux 上还检查媒体文件落盘与恢复。Windows 缺少目录 fsync 契约，三个落盘及恢复集成用例会跳过，不能据此声称 Android 真机已通过。

App 定向检查：`cd app && flutter test test/media/muse_settings_test.dart test/media/media_settings_test.dart test/media/media_catalog_test.dart`。源码接口依据 [muse2api v1.6.11](https://github.com/czg86389-hub/muse2api) 核对；真实账号生成和 Android 安装仍需实际联调。
