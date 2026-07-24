# 查找一行代码和一段逻辑的演变

## 从当前行找到最近一次修改

```bash
git blame -L 20,35 -- src/payment/service.java
```

`git blame` 为文件每行显示最近修改它的提交和作者；`-L 20,35` 限定行范围，`--` 后是路径。

它是调查入口，不是责任判决。格式化、移动代码或批量重构可能让显示的“最后修改者”并非逻辑设计者。

拿到提交 ID 后：

```bash
git show <提交ID>
git log --oneline --decorate <提交ID>~3..<提交ID>
```

阅读提交说明、完整差异和前后上下文。

## 查看文件历史

```bash
git log --oneline -- src/payment/service.java
git log -p -- src/payment/service.java
```

第一条列出触及路径的提交，第二条同时显示差异。文件曾重命名时可以尝试：

```bash
git log --follow -- src/payment/service.java
```

`--follow` 是针对单个文件的重命名追踪启发式，不保证识别所有拆分、合并和大规模移动。

## 查找某段文本何时增减

```bash
git log -S 'legacyDiscount' --oneline --all
```

`-S` 查找使指定字符串出现次数发生变化的提交，适合回答“这个标识何时加入或删除”。

按差异中匹配正则表达式：

```bash
git log -G 'discount.*rate' --oneline --all
```

`-G` 关注新增或删除行是否匹配表达式。两者语义不同；结果为空不证明逻辑从未存在，名称变化或生成代码都可能影响搜索。

## 搜索提交说明

```bash
git log --oneline --grep='payment timeout' --all
```

它搜索提交说明，不搜索代码。工单号、错误码和统一提交前缀能提高可追踪性。

## 调查闭环

先用 blame 或历史搜索缩小范围，再用 `show` 理解整次变更，用测试和运行证据验证因果。不要根据某行作者直接下结论。
