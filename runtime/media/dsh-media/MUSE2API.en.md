# muse2api integration and Android builds

[中文](MUSE2API.md)

This branch extends the existing MIT-licensed dsh-media plugin with Muse image/video profiles. It reuses dsh-go's chat generation modes, media cards, viewers and save actions. Run the muse2api gateway separately; no gateway account/session is embedded in the APK.

## Build in your GitHub fork

Apply these changes to your fork, enable Actions and run **Android + Muse** manually. The workflow uses Ubuntu 24.04, Flutter 3.47.7, Node 24.22.1, JDK 17 and Gradle 9.3.1. It selects the App SDK/NDK from Flutter and installs the native launcher's NDK pinned in `runtime/tawcroot/source.json`, tests the plugin and App, builds the arm64 runtime, invokes `tooling/build-apk.sh`, verifies signing and uploads two artifacts:

- `dsh-go-muse-arm64`: APK for Android 8+ arm64 phones and SHA256SUMS.
- `muse-media-plugin`: `ccch1mneyyy-dsh-media-0.3.1-muse.1.tgz`, documentation and SHA256SUMS.

Tools: [flutter-action](https://github.com/subosito/flutter-action), [setup-android](https://github.com/android-actions/setup-android), [setup-java](https://github.com/actions/setup-java), [Gradle actions](https://github.com/gradle/actions). The workflow does not publish releases. The personal app is **DSH Muse**, package `io.github.carrylin104.musechat`; it installs alongside upstream and the first test APK without replacing their data. Set Actions secrets `MUSE_SIGNING_KEY` (base64 PKCS12, alias `muse`) and `MUSE_SIGNING_PASSWORD` for stable signing. No official signing key is used. Updates target the personal fork; until a Release is published, install the APK provided manually.

## One-tap setup on the phone's local runtime

Download only the APK. Follow onboarding to install the local runtime and configure a chat model, then open **Settings → Images and video → Enable Muse**. The runtime includes `/opt/dsh-go/dsh-media.tgz`; the button installs it with the existing plugin manager. No terminal, shared-storage permission or separate plugin download is needed. Internet access is needed to fetch dependencies the first time. Follow the restart prompt.

Choose **Connect Muse**, enter the service URL and API key, and tap **Save and enable images and video**. Both services share one credential and become their kind's defaults. The form accepts a server root, `/v1`, or `/admin` link and stores the API root. Other services are preserved; configuring the same Muse pair again does not create duplicates. Saving does not verify credentials or generation access.

## Remote hosts and manual installation

Remote hosts do not have the phone's bundled path. Place the separately provided tgz at an absolute path readable by that host, then run in its terminal:

```sh
dsh plugin --profile web add /absolute/path/ccch1mneyyy-dsh-media-0.3.1-muse.1.tgz
```

The original package name is retained for replacement. Record existing settings, follow restart instructions, then verify the local tgz source/version `0.3.1-muse.1`. For a remote host, install it on that host too.

## Configure on the phone

Add and enable **muse2api · Image** and **muse2api · Video** in image/video settings. Profiles/models are `muse-image` and `muse-video`. Set both roots to `http://SERVER:18610/v1` and store the gateway's `MUSE2API_KEY` in host credentials; the two services can share it. Replace the preset loopback placeholder with an address reachable from the host. Do not use `/admin`. A server root gets `/v1` once; reverse-proxy prefixes remain intact. HTTP sends the key and content in plain text; use HTTPS when available.

Select defaults, enter an image/video generation mode and write a prompt. Keep a chat model supporting tool calls, such as the already configured DeepSeek model. Do not assume muse2api's `muse-spark` supports native tool calls merely because its chat endpoint is OpenAI-compatible.

Images use asynchronous `POST /v1/images/tasks`; edits send a reference in JSON `images: [{url: dataURL}]`. Videos use `POST /v1/videos`. Both return background jobs; `get_media_result` produces media cards on completion. Polling never re-POSTs. Known task IDs can resume in the original session using `resume_media(rid)` after host restart; a lost creation receipt without an ID cannot be recovered reliably.

Original files are saved in the host workspace. Bearer auth is sent only to the configured Muse origin, never to third-party CDN links. HTTP/private addresses are accepted only for that explicit Muse origin; other providers retain public HTTPS requirements. The original video downloader still refuses redirects. There is no Muse cancel API: stopping local work does not confirm remote cancellation. Existing approval/budget behavior remains, and its reservation is not a Muse price estimate.

This integration supports one image/request and one PNG/JPEG/WebP reference up to 10 MB. Image ratios: 1:1, 16:9, 9:16, 4:3, 3:4. Video request options: 16:9/9:16, 5/6/8/10 seconds; actual output remains provider-controlled.

## Verify

Run `npm ci --ignore-scripts --no-audit --no-fund && npm test` in `runtime/media/dsh-media`. `test/muse.test.js` uses real local HTTP mocks for task handling, editing payloads, authenticated downloads, lost receipts and origin isolation. Linux also tests publication/recovery; Windows skips three directory-fsync-dependent integration cases. Run `flutter test test/media/muse_settings_test.dart test/media/media_settings_test.dart test/media/media_catalog_test.dart` in `app`.

The protocol was checked against [muse2api v1.6.11](https://github.com/czg86389-hub/muse2api). Live account generation and installation on Android require separate verification.
