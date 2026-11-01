# DidiTingdan 探测版

这是普通 dylib 探测版，不使用越狱注入框架，不执行自动抢单。

## 构建

```bash
make clean package
```

产物是 `DidiTingdan.dylib`，嵌入 `OneTravel.app` 后，用全能签注入并重签。

## 测试顺序

1. 启动应用并登录。
2. 进入司机服务页面。
3. 打开听单，等待一条订单。
4. 手动点击一次接单。
5. 等待请求和结果完成。
6. 通过文件共享导出：

```text
Documents/DidiTingdan/runtime.log
```

## 重点日志

```text
DYLIB_LOADED
APP_LAUNCHED
CLASS_FOUND
CLASS_MISSING
METHOD
REQUEST
RESPONSE
TK_REQUEST
TK_RESPONSE
UI_ACTION
AUTO_GRAB_DISABLED
```

探测版只记录请求、响应、订单 JSON、TK/设备指纹字段、类方法和 UI 操作，不调用自动抢单。
