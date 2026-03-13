# OpenCode iOS Client 测试体系与 Behavior Guard 计划

日期：2026-03-13

## 目标

这份文档有两个目的：

一是把 OpenCode iOS client 当前已有的自动化测试体系讲清楚；二是把后续应该如何为关键交互补上 behavior guard 说清楚，尤其是像这次 session 列表回归这样的问题：底层能力并没有消失，但用户实际走到功能的交互路径被改坏了。

这里的目标不是单纯“把测试数量做多”，而是让产品行为本身变得可描述、可验证，并且在后续 UI 重构、状态层重构、分页策略调整时，不会悄悄把对用户重要的行为改掉。

## 当前测试系统概览

### 测试 Target

仓库当前有两个测试 target：

| Target | 框架 | 作用 | 当前状态 |
| --- | --- | --- | --- |
| `OpenCodeClientTests` | Swift Testing（`import Testing`） | 单元测试、契约测试、状态流测试 | 当前主力测试层 |
| `OpenCodeClientUITests` | XCTest UI Testing | 启动与少量 UI smoke test | 覆盖还比较轻 |

### 主要测试文件位置

- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests.swift`

### 当前单元测试的结构

当前主测试文件 `OpenCodeClientTests.swift` 已经覆盖了几类非常重要的测试：

1. API / 数据契约测试
   - 覆盖 `Session`、`Message`、`Part`、`SSEEvent`、`TodoItem`、`Project`、`QuestionRequest` 等模型的 JSON 解码。
   - 这类测试主要防服务器返回结构变化、optional 字段缺失、兼容字段回归。

2. 业务逻辑 / 纯函数测试
   - 包括 URL 修正、分页 limit 计算、路径规范化、session 删除后的 fallback 选择、session tree 构建等。
   - 这类测试速度快、稳定，适合做行为规则的第一层保护。

3. AppState 状态流测试
   - `AppState` 支持通过 `MockAPIClient` 和 `MockSSEClient` 注入 mock，因此可以在不依赖真实网络的情况下测完整状态变化。
   - 这是目前项目里最有价值的一层集成测试 seam。

4. 子系统专项测试
   - 包括权限请求、SSH helper、Activity tracking、文件路径解析、SSE 路由等。

### 当前 UI Test 的结构

目前 UI test 还比较轻，主要是：

- App 能正常启动
- Chat tab 启动后输入框可见

这说明项目已经具备最基础的 UI smoke test 壳子，但它还不足以保护 session 列表、消息渲染、session 切换、乐观 UI（optimistic UI）这类更复杂的交互行为。

## 当前测试体系的优势

- `AppState` 已经支持依赖注入，这让行为测试比传统强耦合 SwiftUI App 容易很多。
- 仓库已经在把一部分状态变化当作“可测试逻辑”对待，而不是全部藏在 view body 里。
- session 相关的行为已经有初始基础：`buildSessionTree`、`sidebarSessions`、`toggleSessionExpanded`、`loadMoreSessions` 这些都已经是可观察 seam。
- 测试文件虽然集中在一个大文件里，但结构还算清晰，新测试可以沿用现有模式继续加，不需要重新设计一套框架。

## 当前测试体系的缺口

当前系统最擅长的是：

- 数据契约正确性
- 本地状态逻辑正确性

当前系统相对薄弱的是：

- 跨 view-model 边界的用户行为保护

这次 session 列表回归就是一个典型例子：

- `AppState.sessionTree` 本身没有坏。
- `AppState.sidebarSessions` 本身也没有坏。
- 真正坏掉的是 view 选择了错误的数据源，导致用户实际看到的列表行为变了。

所以缺的不是“再来一点普通单元测试”，而是缺一层专门保护用户行为的测试设计。

## 建议采用的测试分层

后续建议把测试系统明确分成四层，每层职责不同。

### Layer 0：契约测试（contract tests）

作用：

- 保护解码结构、optional 字段、wire format、SSE 事件兼容性。

当前已有代表：

- model decoding tests
- SSE event shape tests

### Layer 1：状态 / 业务逻辑测试

作用：

- 保护纯逻辑、确定性状态变换、排序、过滤、选择、分页规则。

当前已有代表：

- `AppState.buildSessionTree(from:)`
- `AppState.nextSessionIDAfterDeleting(...)`
- 分页 helper
- URL / path normalization helper

### Layer 2：带 Mock 的状态流测试

作用：

- 保护跨 API 响应、SSE 事件、`AppState` 编排的行为。

当前已有代表：

- `loadSessions`
- `loadMoreSessions`
- session 切换 / message reload
- 按 `sessionID` 过滤的 message update 行为

### Layer 3：UI smoke tests

作用：

- 保护少数真正关键的用户路径，尤其是“状态没坏，但 UI 接线错了，用户已经用不了了”的情况。

这一层不应该很多。它本质上更慢、更脆，但它是唯一能直接防止“底层状态还对，用户却看不到/点不到”的层。

## 什么叫 Behavior Guard

在这个项目里，behavior guard 应该保护的是下面几类东西：

- 用户可见、可操作、必须持续可达的 workflow
- 跨多层的关键行为不变量
- 已经出现过、而且以后容易重复出现的 bug 模式

它不应该被滥用到纯样式或低价值细节上，除非这些细节本身就是交互的一部分。

典型的 behavior guard 示例：

- child / subagent sessions 在 session 列表层级里仍然可见
- 删除当前 session 后，系统会选中正确的 fallback session
- 非当前 session 的 SSE 更新不会污染当前可见 session
- 发送消息后不会留下重复的 optimistic user row

## 近期重点：Session List 回归保护

### 问题定义

这次 session list 回归的本质，是渲染逻辑从完整 tree 列表切到了 root-only 列表。后端能力没有删，状态模型也没有完全坏，但用户实际可见的交互路径被改变了。

### 建议的保护方式

这一类回归，建议至少用两层去保护。

#### A. 状态流保护

重点加固这些 seam：

- `AppState.sessionTree`
- `AppState.sidebarSessions`
- `AppState.loadMoreSessions()`
- `AppState.toggleSessionExpanded(_:)`

至少要锁住这些不变量：

1. `sessionTree` 必须保留 parent / child 层级关系。
2. `sidebarSessions` 仍然只是 root-only 的分页 helper，而不是完整列表的唯一真相。
3. `loadMoreSessions()` 可以继续补更多 root sessions，但不能让 child hierarchy 从 canonical tree 里消失。
4. archived 过滤要在 tree 与 root-only helper 上保持一致。

#### B. UI 接线保护

再补一条轻量 UI-level guard，用来证明用户实际看到的是 tree 内容，而不是 root-only 内容。

可选方案：

- 如果后面引入 view inspection 工具，可以做 view inspection test。
- 如果不引入，也可以做一条带稳定 accessibility identifier 的 UI smoke test。

这条测试至少要证明：

- child session 可以通过列表 UI 被看到
- 用户可见的 session 列表不是只剩 root sessions

### 为什么两层都需要

如果只有状态测试，那么未来有人可能继续让 `sessionTree` 正常存在，但 view 又一次错误地渲染 `sidebarSessions`，测试仍然不会报。

如果只有 UI test，那么测试会变慢、变脆、定位困难。

最合理的组合是：

- 用状态流测试保护确定性行为
- 用一条轻量 UI guard 保护接线正确性

## 近期测试计划建议

### P0：先保护当前高风险回归

建议优先补：

1. session list hierarchy visibility
2. session pagination vs root-only helper semantics
3. 当前 session 删除后的 fallback 选择
4. 当前 session 才允许触发 reload 的 SSE 行为

### P1：补 1-2 条关键 UI smoke tests

建议候选：

1. Chat tab 启动后可用
2. Session list 可以显示 child session
3. 切换 session 后可见 conversation 内容确实变化

### P2：把重复出现的 bug 模式纳入行为保护

建议候选：

1. 发送后重复 optimistic user message
2. session 切换后遗留 stale streaming row
3. stale async response 导致 file preview 跳动/覆盖

## 关于“发送后偶发重复消息”这个问题的当前判断

这个问题已经先做过一轮后台调研，目前最可能的方向是：

- `appendOptimisticUserMessage()` 先把本地临时 user message append 到 `messages`
- 后续 `loadMessages()` 合并服务端真实消息时，又受 `session.status` / `message.updated` 事件时序影响
- 在某些 race condition 下，旧的 optimistic message 没被正确收掉，新的真实 message 又已经上屏，于是出现“一条正常消息 + 一条底部卡住的重复消息”

另外，底部那条“即使 AI 继续回复，它也不动；切到别的 session 再切回来就恢复”的描述，很像是：

- `runningTurnActivity` 或相关 streaming state 没有及时结束
- session switch 触发了 `resetStreaming()` / `messages = []` / reload，于是 UI 被重新归一化

因此这个问题非常适合在后续作为 P2 behavior guard 候选：

- 一条状态流测试，保护 optimistic message merge 行为
- 一条状态/UI 组合测试，保护 session switch 后不残留 ghost row

## 后续测试 ownership 建议

建议以后按下面这张表判断“一个行为应该测在哪层”：

| 行为类型 | 主测试层 | 次测试层 |
| --- | --- | --- |
| API shape / decoding | model tests | AppState flow tests |
| 确定性状态变换 | pure helper / AppState property tests | AppState flow tests |
| 异步状态编排 | AppState flow tests with mocks | UI smoke tests |
| 用户可见交互可达性 | UI smoke tests | AppState flow tests |
| refactor-sensitive 的跨层行为 | AppState flow tests + 1 条 UI check | 无 |

## 未来改动时的规则

建议后续改动默认遵守下面几条：

1. 只要改动了一个可见 workflow，就应该在同一个分支里补一条回归测试，或更新已有测试。
2. 如果一个改动改变了 view 的数据源选择，就应该补一条 guard，证明用户原本能走到的交互路径仍然可达。
3. 如果一个 bug 的表现是“切一下 session / 刷新一下 / 重新打开页面就好了”，那很可能不是纯逻辑 bug，而是状态与展示之间的跨层 bug，不应只用 helper test 草草覆盖。
4. UI tests 要尽量窄，重点验证 reachability，不要去测大量容易变化的排版和文案。
5. 除非问题明确出在 UI 接线，否则优先选择带 mock 的确定性状态流测试，而不是上来就做大而重的端到端测试。

## 推荐验证方式

涉及测试相关改动时，建议使用这些命令做验证：

```bash
xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'generic/platform=iOS Simulator'
xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

注意：

- 本地 simulator 基础设施可能独立出问题，这和应用代码本身不一定有关。
- 如果遇到 simulator clone / creation state 之类的问题，`build` 通过仍然有编译层价值，但需要明确记录“测试环境失败”和“代码验证失败”不是一回事。

## 这份计划之后的直接落地项

1. 补一条 regression test，明确锁住 `sessionTree` 与 `sidebarSessions` 的职责边界。
2. 补一条 regression test，覆盖 child sessions 挤占第一页时的分页行为。
3. 在 accessibility hook 稳定后，补一条轻量 UI smoke test，确认 session list hierarchy 可见。
4. 用同一套思路继续调查并保护“发送后重复 optimistic user row / ghost row”问题。

## 总结

OpenCode iOS client 当前其实已经有一套不错的单元测试和状态流测试基础。真正缺的不是“完全没有测试”，而是缺少一套明确的 behavior guard 思路，去保护那些对用户重要、但又很容易在接线或重构中被悄悄改坏的行为。

这份文档的核心主张是：继续把 contract tests 和 flow tests 作为骨架，再在真正值得的地方补极少量 UI guard。这样才能既保持测试速度和可维护性，又能更早抓住那些用户会第一时间感知到的回归。
