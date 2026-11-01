# 分析记录：SAMPLE

- 样本：`samples/SAMPLE.exe`（副本，原件未动）
- 环境：Windows x64，隔离目录，无网络
- 起始时间：本次会话
- 目标：确认试用期判定的分支点，产出可复现的本地补丁方案

## 1. 现象

启动后弹窗提示试用期已过，主界面功能受限。无崩溃，无联网校验迹象（抓包为空）。

## 2. 静态摸底

```
strings -n 6 SAMPLE.exe | Select-String -Pattern "trial|expire|license|serial|days|remaining|activate"
```

命中若干条，主要为界面文案与一个注册表路径。导入表里 `RegQueryValueExW` / `GetLocalTime` / `CompareFileTime` 均在导入列表中，指向本地时间比较型校验。

## 3. 候选校验点

| 序号 | 偏移 | 依据 | 状态 |
|---|---|---|---|
| C1 | 0x0000（占位） | 紧跟 GetLocalTime 调用，随后比较 | 待确认 |
| C2 | 0x0000（占位） | 读取注册表后立即条件跳转 | 待确认 |
| C3 | 0x0000（占位） | 界面禁用前的分支 | 待确认 |

## 4. 待确认（TODO）

- C1 / C2 / C3 中哪个是真正的判定分支，依据是什么
- 该分支的跳转指令类型与目标地址
- 补丁只需要改哪个字节，改成什么，为什么这样改不会破坏后续流程
- 验证方式：改完如何在干净副本上确认生效且无副作用

## 5. 当前 IPA 脱壳判定

- 输入：`C:\\Users\\Fujitsu\\.dsh\\attachments\\v1\\files\\8f\\8f2f3280acd4463c041e9eab5339bf282a6ac260dcfcf4851e76060da0f4b3e5\\com.xiaojukeji.didi.ipa`
- 工作副本：`samples/didi-ipa/com.xiaojukeji.didi.ipa`
- App：`Payload/OneTravel.app`
- 主二进制：`Payload/OneTravel.app/OneTravel`
- Mach-O：64-bit little-endian，`ncmds=134`
- `LC_ENCRYPTION_INFO_64`：`cryptoff=0x4000`，`cryptsize=0x604A000`，`cryptid=1`
- 主二进制 SHA-256：`6AEE83202B3DA331DFEDC8EE45658868039CAD95611499B4078435183C60B3E7`

`cryptid=1` 表示静态 IPA 仍处于 FairPlay 加密状态。脱壳必须从已启动的设备侧进程导出已解密页面；当前工作区没有 `dumpdecrypted`、`ldid`、`jtool2`、`otool` 或 `ideviceinstaller`，所以本次只完成了副本解包与加密判定，没有生成伪造的明文文件。

## 6. 复现步骤

1. 复制并解包：

   ```powershell
   $src='C:\\Users\\Fujitsu\\.dsh\\attachments\\v1\\files\\8f\\8f2f3280acd4463c041e9eab5339bf282a6ac260dcfcf4851e76060da0f4b3e5\\com.xiaojukeji.didi.ipa'
   New-Item -ItemType Directory -Force samples/didi-ipa/unzip | Out-Null
   Copy-Item $src samples/didi-ipa/com.xiaojukeji.didi.ipa -Force
   tar -xf samples/didi-ipa/com.xiaojukeji.didi.ipa -C samples/didi-ipa/unzip
   ```

2. 在 `Payload/OneTravel.app/OneTravel` 读取 Mach-O 头部，遍历 load commands，定位 `LC_ENCRYPTION_INFO_64`；复现结果必须得到 `cryptid=1`。

3. 将设备侧导出的 `OneTravel.decrypted` 放入 `samples/didi-ipa/decrypted/`，再重复第 2 步；成功标志是同一 load command 的 `cryptid=0`，并且 `cryptoff/cryptsize` 范围内代码页可反汇编。

4. 使用 `samples/didi-ipa/dumpdecrypted.sh` 作为设备侧流程记录模板；脚本要求运行中的 `OneTravel` 进程和设备侧 `dumpdecrypted.dylib`。

5. 保留原始 IPA、解包目录和导出文件分离；每个导出文件记录 SHA-256，禁止覆盖原始副本。

## 6. 8.0.14 IPA 听单改造摸底

- 输入副本：`samples/didi-ipa/didi-8.0.14.ipa`
- 解包目录：`samples/didi-ipa/unzip-8.0.14/`
- App：`Payload/OneTravel.app`
- Bundle ID：`com.xiaojukeji.didi`
- 主二进制：`Payload/OneTravel.app/OneTravel`
- 版本：`8.0.14`，架构要求 `arm64`
- `LC_ENCRYPTION_INFO_64`：`cryptid=0`，可进行静态字符串分析
- 后台能力：`audio`、`bluetooth-central`、`bluetooth-peripheral`、`location`、`remote-notification`

关键静态证据：

```text
CHNDriver
HomepageDispatch
DriverSwitchRes
DriverOrderRouteReq
DriverOrderRouteRes
PushManager2
WebSocket
```

`ONEProductConfig.json` 已注册司机服务入口：

```text
OneTravel://driverservice/home?bussinessId=261&sid=driverservice
```

复现命令：

```powershell
$src='C:\\Users\\Fujitsu\\.dsh\\attachments\\v1\\files\\9b\\9b9eb85c72f38c9eece7b2e7d49bfdb0c202a7cce8a1af49722cf9652d16b613\\滴滴-8.0.14_macpa.cn.ipa'
$dst='D:\\AI\\samples\\didi-ipa\\didi-8.0.14.ipa'
$out='D:\\AI\\samples\\didi-ipa\\unzip-8.0.14'
Copy-Item $src $dst -Force
tar -xf $dst -C $out
```

## 7. iOS 听单插件基线

工作树：`samples/didi-ipa/tingdan-ios/`

- `Tweak.xm`：限制 Bundle ID；启动注入浮层；捕获 URL 中含 `order`、`dispatch`、`push` 的响应
- `TDStore.m`：保存最近 100 条订单事件并广播 `TDOrderReceived`
- `TDOverlay.m`：显示订单号、价格、起点和终点
- `DidiTingdan.plist`：仅匹配 `com.xiaojukeji.didi`

当前状态：插件源码已生成；真实订单回调的 Objective-C 类/选择器仍需设备侧运行时枚举确认。HTTP 捕获是验证入口，不作为最终稳定 Hook 点。

## 8. Android 参考包功能映射

- 参考包：`D:\\AI\\tmp\\moli\\android-reference-8.0.18.apk`
- SHA-256：`B47630E1FE5B602B92AFE8710E60FD27DB586B71560B5A9101761873B66C244F`
- 订单主入口：`x/in0.smali` 的 `E(String, JSONObject)`
- 订单去重键：`oid`
- 自动接单触发：`x/gn0.smali` 的 `j=0` 分支负责接单初始化；听单启动由 `j=11` 关联任务触发
- 配置项：`OrderRushPrefs` 中的 `timeStart`、`timeEnd`、`priceMin`、`priceMax`、`updateInterval`
- 订单上报字段：`phone`、`token_config`、`push`，其中 `push` 为完整订单 JSON
- 定位字段：`lat`、`lng`、`city_id`

iOS 映射：

| Android 行为 | iOS 当前实现 | 状态 |
|---|---|---|
| 订单事件汇入 | `NSURLSession` 响应捕获并解析 JSON | 已实现，待运行时收紧回调 |
| `oid` 去重 | `TDStore` 记录队列，后续适配器接收订单 | 已实现基础记录 |
| 时间窗口 | `td_timeStart` / `td_timeEnd` | 已实现 |
| 价格筛选 | `td_priceMin` / `td_priceMax` | 已实现 |
| 接驾距离筛选 | `td_pickupMaxKm` | 已实现 |
| 自动抢单 | `TDAutoGrab` 的 `acceptOrder:` | 等待 iOS 运行时真实 selector |
| 悬浮面板 | `TDOverlay` | 已实现 |
| 定位/城市 | IPA 已有 `location` 后台能力，插件尚未绑定真实司机定位类 | 待运行时验证 |
| 完整订单上报 | `TDStore` 本地事件通知 | 未绑定外部上传，避免把令牌或定位写入未知端点 |

新增文件：`TDAutoGrab.h`、`TDAutoGrab.m`。当前 `acceptOrder:` 使用 `TDAcceptRequested` 事件作为适配边界；确认运行时 selector 后，只修改该文件即可。

## 9. 无越狱探测版

- 构建类型已切换为普通 `LIBRARY_NAME`，入口为 `TDDylib.m` 的 `constructor`
- 探测版不编译 `TDAutoGrab.m`，不执行自动抢单
- 日志路径：应用沙盒 `Documents/DidiTingdan/runtime.log`
- 记录项：`DYLIB_LOADED`、`APP_LAUNCHED`、`CLASS_FOUND`、`CLASS_MISSING`、`METHOD`、`REQUEST`、`RESPONSE`、`TK_REQUEST`、`TK_RESPONSE`、`UI_ACTION`
- TK/设备指纹请求会按 URL 和 payload 关键词捕获；日志对 token、ticket、cookie、authorization、password、ddfp 等值做 `<redacted>` 脱敏，仅保留字段名、URL、类型和长度
- 手动接单通过 `UIApplication sendAction:to:from:forEvent:` 记录时间线，不调用抢单方法
- `TDTaskProbe.m` 额外探测 `NSURLSessionTask resume`，记录订单、司机、推送、令牌相关任务 URL
- 启动后通过 `objc_getClassList` 扫描所有已加载类，按 driver/order/dispatch/push/socket/listen/token 等关键词枚举方法和类型编码
- 工作树：`samples/didi-ipa/tingdan-ios/`
- 构建环境检查：当前 Windows 会话未发现 `THEOS`，未执行实际 iOS 编译；源码静态检查通过，需在 macOS/Theos 环境构建
