# iOS TestFlight 上传记录（本地命令行）

## 当前项目参数

- App 名称：`AI吉他`
- Bundle ID：`com.wanghan.guitarhelper`
- Team ID：`7R8RS88G2M`
- IPA 路径：`/Users/wanghan/Documents/guitar-ai-coach/flutter_app/build/ios/ipa/AI吉他.ipa`

## App Store Connect API（用于 altool 上传）

- Issuer ID：`69a6de7f-1b6d-47e3-e053-5b8c7c11a4d1`
- Key ID：`QVH82YP7W2`
- 本机私钥文件：`/Users/wanghan/Documents/guitar-ai-coach/flutter_app/ios/AuthKey_QVH82YP7W2.p8`
- altool 读取私钥位置：`~/.private_keys/AuthKey_QVH82YP7W2.p8`

## 一次性准备（首次或换机器）

```bash
mkdir -p "$HOME/.private_keys"
cp "/Users/wanghan/Documents/guitar-ai-coach/flutter_app/ios/AuthKey_QVH82YP7W2.p8" "$HOME/.private_keys/AuthKey_QVH82YP7W2.p8"
chmod 600 "$HOME/.private_keys/AuthKey_QVH82YP7W2.p8"
```

## 每次打包并上传（本机）

> 注意：上传前先递增 `flutter_app/pubspec.yaml` 的 build 号（`version: x.y.z+build` 中 `build` 必须递增）。

```bash
cd "/Users/wanghan/Documents/guitar-ai-coach/flutter_app"
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --export-options-plist=ios/ExportOptions.plist
xcrun altool --upload-app --type ios -f "/Users/wanghan/Documents/guitar-ai-coach/flutter_app/build/ios/ipa/AI吉他.ipa" --apiKey "QVH82YP7W2" --apiIssuer "69a6de7f-1b6d-47e3-e053-5b8c7c11a4d1"
```

## 最近一次成功上传记录

- 时间：`2026-04-13`
- 结果：`UPLOAD SUCCEEDED with no errors`
- Delivery UUID：`8c5d3347-9c3d-4098-8e61-2067e0e1c06b`
