# 架构与不可破坏约束

开始修改前完整阅读本文件、README 和 `../CODEX_TASK.md`。技术栈固定为 Vanilla JS ES Modules、Vite、ECharts、Web Serial、IndexedDB。

## 不变量

1. UI 禁止直接访问 SerialPort。
2. ChartController 禁止解析协议。
3. ProtocolDecoder 禁止操作 DOM。
4. ProtocolEncoder 禁止操作 DOM。
5. 浏览器源码禁止硬编码 PARAM_ID 的业务名称。
6. DATA_TYPE 的 RAW ↔ Human 转换只能由 ValueCodec 负责。
7. 所有 SET_PARAM 必须经过 ProtocolEncoder。
8. 所有真实串口发送必须经过 SerialTransport；MockTransport 只模拟设备。
9. ChannelStore 是实时 Channel 状态的唯一真源。
10. ConfigStore 是 Channel UI 配置的统一管理者。
11. 隐藏 Channel 不能停止数据接收或记录。
12. Chart 刷新频率与 UART 接收频率必须解耦。
13. 历史数据库与实时 RingBuffer 必须解耦。
14. Communication Log 不得无限增长。
15. 新增 FPGA Telemetry Channel 原则上不得要求修改网页源码。
16. 可写参数由用户配置 writable 决定，不根据名字硬编码。
17. PARAM_ID 只是机器唯一 Key，不等同于 UI 名称。
18. 任何 Agent 修改架构前必须先阅读 ARCHITECTURE.md。

## 模块边界

| 文件 | 职责 / 边界 |
| --- | --- |
| serial/SerialTransport.js | Web Serial 所有权、授权、8N1、字节读写、串行写队列、锁释放、连接状态 |
| serial/MockTransport.js | 虚拟设备，合法 Telemetry 分块输入，验证 SET_PARAM 并在 Telemetry 里回读 |
| protocol/CRC16.js | 无状态 CRC 计算 |
| protocol/ValueCodec.js | 符号、补码、量化、类型边界、未知类型 fallback |
| protocol/ProtocolEncoder.js | 唯一 SET_PARAM 编码入口，TX SEQ；Telemetry frame helper 仅给 Mock/测试用 |
| protocol/ProtocolDecoder.js | 有限内部流缓冲、同步、LEN/COUNT/版本/CRC 校验，frame / telemetry / error 事件 |
| store/ChannelStore.js | ID Map、最新数据、seen、请求回读状态、SEQ 统计、每通道有限 RingBuffer |
| store/ConfigStore.js | v1 localStorage Schema、验证、持久化、损坏与配额 fallback |
| chart/ChartController.js | 单图、25 FPS、双 Y、DataZoom、统一 Tooltip、实时/暂停/历史视图 |
| control/ParameterController.js | 用户范围 / 可写检查、50ms 节流、最后值发送、Requested RAW 及 Telemetry 同步 |
| recorder/HistoryStore.js | Session、批量事务、Stop flush、失败保留批次、窗口查询、分页 CSV、删除/重命名 |
| logger/FrameLogger.js | 最多 2000 条记录，Raw HEX，独立于数据记录 |
| app/AppController.js | 组合上述模块，DOM 与用户事件，每 200ms 更新 UI/日志 |
| core/Events.js | 无跨层依赖的轻量订阅机制 |

接收数据流：Transport 的 bytes 事件交给 ProtocolDecoder；合法 Telemetry 交给 ChannelStore。Chart 仅读取 Store；UI 读取 Store；Recorder 订阅 Store frame 事件。Decoder error/frame 事件写诊断日志，不修改 DOM。

发送数据流：Slider / Numeric Input 将 human value 交给 ParameterController；ValueCodec 检查和量化；ProtocolEncoder 创建字节；当前 Transport.write 发送。成功发送后日志包含实际 RAW 与完整帧；ChannelStore 的后续样本比较 Requested 的 TYPE / rawBits。无 ACK、无自动重发。

## 存储 Schema v1

`fpga-monitor-config-v1` 的顶层为 `{version:1, channels:{[decimalId]:config}, ui:{baud,timeWindow,left,right,logFilters}}`。channel config 只包含 name/unit/visible/color/axis/writable/sliderMin/sliderMax/sliderStep。首次发现自动保存默认配置；设备实际类型以每次 Telemetry 为准。不序列化 SerialPort、实时值或实验数据。

`fpga-monitor-db-v1`，IndexedDB version=1：

- sessions，keyPath=id：UUID、名称、ISO 开始/结束、协议版本、durable frames/samples/duration/status、通道快照、sourceStart。
- frames，keyPath=[sessionId,ordinal]，ordinal 单调递增，独立于可能回绕的 SEQ；time index=[sessionId,time]。
- frame 数据含 seq、performance.now() hostReceiveTime、Session 相对 time、samples；每个 sample 包含 sourceId/type/rawBits/rawValue/value。

DB 和 localStorage 版本不可随意变更；未来改 Schema 必须显式迁移。配置损坏安全 fallback 并 ERR。事务将最多 250 帧和这些已提交帧对应的 Session 元信息一起提交；最多一个 flush job，避免慢磁盘导致无限 Promise 队列。失败批次退回 pending 并报错，可 Stop 重试。积压上限 5000 帧，超限明确停止接收记录数据；活动 Session 不可导出或删除。

中断恢复只修改 recording→interrupted，不伪造结束时间。已提交帧完整保留，浏览器突然退出不能保证未提交 RAM 数据。CSV 读取固定 500 帧分页，最后 Blob 仍占导出文件对应内存；窗口查询使用时间索引和每通道固定桶 min/max，不加载完整 Session 到 Chart。

## 容量、时间和渲染

每 Channel 20,000 点；最多 256 个 ID。日志最多 2000 条，DOM 只显示过滤后的最近 150 条。Decoder 每个字节推进状态，保留最多 Header + 1531 Payload + CRC，不依赖 read() 边界。协议以 COUNT 校验 LEN，坏帧移走首字节后重新找帧头，支持 A5 A5 5A。

LIVE 只绘制选定的可视时间范围；每条线 min/max 降采样至约 3000 点。缩放/平移不改变mode；ChartController的xView保存相对referenceEnd的秒数偏移，referenceEnd在LIVE为最新接收时间、PAUSE为冻结时刻、history为加载窗口末端。每次绘图重算绝对startValue/endValue，保持跨度并随接收时间推进。左键按像素位移自由平移X和双Y，不夹紧到默认窗口边界；按新范围查询有限RingBuffer或已有冻结/历史数据，空白区域不补造样本。

导航由ChartController统一处理pointer和wheel；绘图区滚轮绕鼠标坐标缩放X及双Y，X轴区域仅缩放X，两侧Y轴区域仅缩放对应Y。以convertFromPixel取各轴锚点，边界按anchor+(boundary-anchor)*factor更新。移除inside DataZoom以避免原生手势重复处理或边界夹紧，保留概览slider并将其datazoom值转为相对偏移。双Y临时范围及X偏移不写入配置Schema。窗口级pointerup/cancel/blur结束拖动；回到拖动起点恢复初始范围。RESET VIEW恢复完整时间窗和已保存的Auto/Manual Y范围，保持mode；LIVE同时清除临时导航并返回最新数据。主题为白色面板、灰色虚线网格及蓝色控件；ConfigStore的新通道Palette适配白底，已有颜色配置不迁移。

PAUSE仅由显式按钮触发，复制有限缓存，避免未来 RingBuffer 覆盖造成已暂停波形改变；缩放、重复PAUSE或切换时间窗不重新捕获正在接收的数据，接收和记录不受影响。暂停波形先按当前时间窗筛选，再降采样；历史只加载选择窗口，单通道最多4000点。切回LIVE不改变实验记录。刷新使用requestAnimationFrame 40ms节流；协议回调从不直接setOption。

连接开始使用 performance.now() 相对秒；记录从点击 Record 的主机时间起算。Frame timestamp 是完整帧完成读取的 host time，一次 read 粘连多帧可能有相同时间。为未来 FPGA timestamp 保留独立 frame 字段的扩展位置，但 V1 不编造 FPGA 采样时刻。SEQ 前向模差 <32768 统计 lost，自然处理 FFFF→0000；重复/旧帧有独立统计且不移动前向基准。设备复位后重新连接。

## 维护与测试

协议代码变动必须同步确定字节和 CRC 参考向量、拆包/粘包/恢复测试。状态测试检查可写门控、节流、同步、隐藏接收及持久化；fake-indexeddb 检查事务、CSV、窗口、恢复；SerialTransport 测试使用实际 JS ReadableStream/WritableStream 替代硬件。

完成修改必须执行 npm run test 和 npm run build。真实硬件联调单独记录，不得以 Mock 或 fake IndexedDB 测试替代硬件已验证的结论。
