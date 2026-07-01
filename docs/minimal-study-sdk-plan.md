# 极简自习 SDK 计划（加入静默多人协同与个人学习数据统计）

> 状态：已按本计划落地 Flutter/Dart SDK、UI、示例、资产与测试。

## Summary

- 在现有 Flutter/Dart SDK 上新增一套本地优先的“个人自习套件”，不改动现有在线自习房、聊天、后端 API 主线。
- 交付为 `study_room_sdk` 逻辑模型/控制器 + `study_room_ui` 开箱即用 Flutter 组件。
- 默认支持 7 个模块：番茄钟、今日目标、学习记录、个人学习数据统计、背景音库、自定义背景、静默陪伴列表。
- 数据默认本地保存；背景音音频文件内置在 UI 包 assets 中，并允许接入方传入自定义音源。
- 新增统计保持个人可见，不进入静默陪伴列表，不展示给同房间其他用户。

## Public APIs / Types

- `PomodoroPreset`: 支持 `25/5`、`50/10`、自定义。
- `PomodoroConfig`: 配置专注时长与休息时长，默认 `25/5`。
- `PomodoroController`: 提供 `start()`、`pause()`、`resume()`、`end()`。
- `TodayGoal`: 一句话目标、可选目标番茄数、完成状态。
- `StudyDayRecord`: 记录每日专注时长与番茄数。
- `StudyTaskRecord`: 记录任务完成/未完成。
- `StudyStats`: 今日专注时长、今日番茄数、连续学习天数、最近 7 天趋势。
- `StudyReport`: 日/周/月报统一模型。
- `StudyReportRange`: `day`、`week`、`month`。
- `StudyAnalytics`: 计算专注时长、连续打卡天数、任务完成率、趋势和报告摘要。
- `StudyAnalyticsView` / `StudyReportView`: 可视化个人进步与报告的 UI 组件。
- `StudySoundTrack`: 内置雨声、白噪音、咖啡馆、图书馆、键盘声，并支持接入方传自定义音源。
- `StudyBackground`: 支持颜色背景、图片背景、渐变背景和遮罩强度。
- `SilentCompanionList`: 可选静默陪伴头像列表组件。
- `SilentCompanionTheme`: 配置头像尺寸、状态边框颜色和状态图标映射。
- `StudyFocusKitView.showCompanions`: 控制是否显示静默陪伴列表。

## Implementation Changes

- 番茄钟：
  - 默认 `25/5`，支持 `50/10` 和自定义。
  - 支持开始、暂停、继续、结束。
  - 完成番茄后自动写入学习记录。
- 今日目标：
  - 支持一句话目标。
  - 支持可选目标番茄数。
  - 支持完成勾选。
- 学习记录：
  - 统计今日专注时长。
  - 统计今日番茄数。
  - 统计连续学习天数。
  - 展示最近 7 天趋势。
- 个人学习数据统计：
  - 记录每位用户本地个人专注时长、连续打卡天数、任务完成率。
  - 基于本地 `StudyDayRecord`、`TodayGoal` 和任务记录生成日/周/月报。
  - 可视化展示趋势、完成率和阶段总结，突出进步与成就感。
  - 不把个人统计写入房间成员状态，不在静默陪伴列表展示。
- 背景音库：
  - 内置雨声、白噪音、咖啡馆、图书馆、键盘声。
  - 支持播放/暂停、音量控制、循环播放。
  - 支持接入方传自定义音源。
- 自定义背景：
  - 支持颜色背景、图片背景、渐变背景。
  - 支持控制遮罩强度，保证 UI 可读。
  - SDK 不内置复杂视觉场景。
- 静默多人协同：
  - 复用现有 `StudyRoom.members` 和 `PresenceStatus`。
  - 只展示同房间其他在线用户头像和昵称。
  - 用头像边框或状态图标展示状态。
  - 不展示具体专注时长、番茄数或趋势，避免攀比焦虑。
  - 成员变化平滑更新，无弹窗、无提示音。

## Test Plan

- 番茄钟：
  - 默认 `25/5`、`50/10`、自定义配置正确。
  - 开始、暂停、继续、结束状态流转正确。
  - 完成番茄自动记录。
- 今日目标：
  - 一句话目标可保存。
  - 可选目标番茄数可显示。
  - 完成勾选状态正确。
- 学习记录：
  - 今日专注时长统计正确。
  - 今日番茄数统计正确。
  - 连续学习天数统计正确。
  - 最近 7 天趋势补齐无数据日期。
- 个人学习数据统计：
  - 专注时长按日/周/月聚合正确。
  - 连续打卡天数跨空档中断，跨连续日期累加。
  - 任务完成率在无任务、部分完成、全部完成场景下计算正确。
  - 日/周/月报生成范围正确，并补齐无数据日期。
  - `StudyAnalyticsView` / `StudyReportView` 不渲染他人数据。
- 背景音库：
  - 内置音源可渲染。
  - 播放/暂停状态正确。
  - 音量控制正确。
  - 自定义音源可接入。
- 自定义背景：
  - 颜色、图片、渐变背景渲染正确。
  - 遮罩强度可控，并保证 UI 可读。
- 静默陪伴列表：
  - 过滤当前用户和离线用户。
  - 不渲染可攀比数据。
  - 状态视觉映射正确。
  - 成员变化时列表稳定更新。

## Assumptions

- v1 统计数据默认本地保存，仅属于当前用户。
- v1 日/周/月报为本地生成，不新增后端 API。
- v1 任务完成率基于今日目标/任务记录，不引入复杂任务管理系统。
- v1 静默多人协同交付 Flutter 可嵌入组件，不新增原生 JS Web Component 包。
- v1 不新增后端 API，只基于现有房间成员与实时事件实现静默陪伴。
- v1 保持 SDK 极简，不内置复杂视觉场景。

## Verification

- `cd packages/study_room_sdk && dart test`
- `cd packages/study_room_ui && flutter test`
- `cd apps/example_flutter && flutter test`
- `cd packages/study_room_sdk && dart analyze`
- `cd packages/study_room_ui && flutter analyze`
- `cd apps/example_flutter && flutter analyze`
