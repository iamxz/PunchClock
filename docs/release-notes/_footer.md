---

## 安装

1. 下载本页 Assets 里的 `Daka-<版本>.pkg`，双击即可安装到 `/Applications/小打卡.app`；或下载 `Daka-<版本>.app.zip`，解压后拖入「应用程序」。
2. 安装前请先**退出正在运行的旧版本**（主窗口「设置 → 系统与启动 → 退出应用」），否则安装器覆盖运行中的 app 可能失败。
3. 校验下载完整性：

   ```sh
   shasum -a 256 -c checksums.txt
   ```

## 首次打开放行（Gatekeeper）

本应用为 **ad-hoc 签名**，安装包**未签名、未公证**，别人首次打开会被 Gatekeeper 拦截，任选一种放行：

- 右键 pkg →「打开」
- 系统设置 →「隐私与安全性」→「仍要打开」
- 若仍提示「已损坏 / 无法验证开发者」：

  ```sh
  xattr -dr com.apple.quarantine /Applications/小打卡.app
  ```
