# FPGA Monitor 维护规则

修改前必须完整阅读：

1. README.md
2. ARCHITECTURE.md
3. ../CODEX_TASK.md（本上位机的 CODEX_TASK.md 来源，唯一任务书，不复制分叉）

保持模块职责，不为了省事跨层调用。所有主要 JS 文件保留 Responsibility / Allowed dependencies / Forbidden responsibilities / Public API / Architecture invariants 文件头。

不要无原因更改 Protocol V1。只实现 PC→FPGA SET_PARAM，不加入 GET_PARAM、COMMAND、ACK 等指令。DATA_TYPE 转换只在 ValueCodec；发送字节只由 ProtocolEncoder 创建，真实串口只由 SerialTransport 访问。

不要硬编码 Channel 业务含义。PARAM_ID 唯一标识；名称、单位、轴、颜色、隐藏状态、writable、Slider 范围由 ConfigStore 管理。未知 ID 自动创建，未知类型保留 RAW。隐藏通道不能影响接收、缓存和记录。

不得取消 RingBuffer、Logger、记录积压和历史绘图容量限制。图表不得逐帧全量重绘，历史不得一次性放入全部 Session。不得未经迁移改变配置或 DB Schema。

修改协议代码必须同步更新测试，完成修改后必须运行 `npm run test` 和 `npm run build`，修改交互还应实际检查 Demo。不得将未测试硬件描述为已验证。

只修改 PC 上位机相关文件，保留既有 FPGA RTL、协议文档、资料和用户暂存变更。遵循工作区 Python 专用环境、Claude_Temp 临时文件与 Claude_Change.md 追加记录规则。无需引入 UI 框架、云服务或系统级安装。
