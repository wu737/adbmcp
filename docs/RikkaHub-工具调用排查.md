# RikkaHub「当前模型未开启工具调用」—— 根因与修复

> 根因已通过 RikkaHub 源码 (`ChatService.kt` / `Model.kt` / `ModelRegistry.kt` / `SettingProviderDetailPage.kt`) 完全定位。

## 一句话结论

**RikkaHub 判断"模型支不支持工具调用"时，看的是模型配置里【已保存的】`abilities` 字段，而不是实时查询 models.dev。**
你的 `deepseek-flash` 这个模型记录里 `abilities` 是空的，所以即使模型本身完全支持工具调用，App 也会报这个错。

---

## 源码证据链

### 1. 报错触发点 —— `ChatService.kt`

```kotlin
private fun warnIfToolsUnavailable(turn: ChatTurnContext, conversationId: Uuid) {
    if (ModelAbility.TOOL in turn.model.abilities) return   // ← 只看已保存的 abilities
    if (shouldUseExternalWebSearch(turn.assistant, turn.model) ||
        mcpManager.getAllAvailableTools(turn.assistant).isNotEmpty()
    ) {
        addError(
            IllegalStateException(context.getString(R.string.tools_warning)),
            conversationId,
            title = context.getString(R.string.error_title_tool_unavailable)
        )
    }
}
```

> 官方 Issue #276 里作者 re-ovo 的解释：
> 「因为你用了需要工具调用的功能：搜索/记忆/MCP，但是模型不支持工具调用」

### 2. `abilities` 默认值是空 —— `Model.kt`

```kotlin
@Serializable
data class Model(
    val modelId: String = "",
    val displayName: String = "",
    val inputModalities: List<Modality> = listOf(Modality.TEXT),
    val outputModalities: List<Modality> = listOf(Modality.TEXT),
    val abilities: List<ModelAbility> = emptyList(),   // ← 默认空
    ...
)

@Serializable
enum class ModelAbility {
    TOOL,
    REASONING,
}
```

### 3. 能力本该被自动填充 —— `ModelRegistry.kt`

```kotlin
private val DEEPSEEK_FLASH = defineModel {
    tokens("deepseek", "flash")
    visionInput()
    toolReasoningAbility()      // ← 含 TOOL
}
```

且优先查 models.dev：

```kotlin
val MODEL_ABILITIES = ModelData { modelId ->
    val abilities = catalog?.find(modelId)?.abilities
        ?: resolveModels(modelId).flatMap { it.abilities }.toSet()
    buildList {
        if (ModelAbility.TOOL in abilities) add(ModelAbility.TOOL)
        if (ModelAbility.REASONING in abilities) add(ModelAbility.REASONING)
    }
}
```

**实测 models.dev 数据**（`https://models.dev/api.json`）：
```
deepseek-flash          tool_call=True  reasoning=True
deepseek-v4-flash       tool_call=True  reasoning=True
deepseek-v4-pro         tool_call=True  reasoning=True
```

**两条路径本该都给出 TOOL** —— 说明自动填充发生在「添加模型」那一刻，
而你这条模型记录是在该逻辑生效前添加的，或添加时没触发填充，**空 abilities 被保存了下来**。

### 4. 模型编辑界面可以手动补上 —— `SettingProviderDetailPage.kt`

```kotlin
if (model.type == ModelType.CHAT) {
    ModalAbilitySelector(
        abilities = model.abilities,
        onUpdateAbilities = { onModelChange(model.copy(abilities = it)) }
    )
}

@Composable
fun ModalAbilitySelector(abilities: List<ModelAbility>, onUpdateAbilities: (List<ModelAbility>) -> Unit) {
    Text(stringResource(R.string.setting_provider_page_abilities), ...)
    ConnectedMultiChoiceButtons(
        options = ModelAbility.entries,
        selected = abilities,
        onToggle = { ability, checked ->
            onUpdateAbilities(if (checked) abilities + ability else abilities - ability)
        }
    ) { ability, selected ->
        ConnectedChoiceLabel(
            text = stringResource(
                when (ability) {
                    ModelAbility.TOOL -> R.string.setting_provider_page_tool
                    ModelAbility.REASONING -> R.string.setting_provider_page_reasoning
                }
            ), ...
        )
    }
}
```

保存链路：`onUpdateAbilities` → `model.copy(abilities = it)` → `dialogState.confirm()`
→ `providerSetting.editModel(editedModel)` → 写入 DataStore。

---

## 修复步骤

### 1. 编辑模型，开启「工具调用」（关键）

```
设置 → 提供商 → 点进 DeepSeek(或你配置的提供商)
  → 底部「模型」标签 → 点 deepseek-flash 卡片
  → 弹窗切到「基本设置」标签页
  → 找到「能力」区块
  → 打开「工具调用」(TOOL) 开关
  → 顺便打开「推理」(REASONING)（可选，deepseek-flash 支持）
  → 点「确认」保存
```

### 2. 输入模态（可选）

同一弹窗的「输入模态」里，如果要用图片输入，打开「图像」(IMAGE)。
`deepseek-flash` 在 models.dev 里也支持 image。

### 3. 新建对话再测

模型能力在**创建对话时**注入请求，必须新建会话。

---

## 备选方案

### A. 删掉模型重新添加

把 `deepseek-flash` 模型条目删除，重新添加一次 ——
新的条目会走 `MODEL_ABILITIES` 自动填充，TOOL/REASONING 会被正确写入。

### B. 换个模型 ID

如果删了重加还是不行，把模型 ID 改成 `deepseek-v4-flash` 或 `deepseek-v4-pro`
（这两个在 RikkaHub 的 `ModelRegistry` 里有显式定义，匹配更可靠）：

```kotlin
private val DEEPSEEK_V4_FLASH = defineModel {
    tokens("deepseek", "v", "4", "flash")
    toolReasoningAbility()
    contextLength(1.m)
}
```

DeepSeek 官方 API 确认可用（`GET /models` 实测返回）：
```
deepseek-flash
deepseek-v4-pro
```

### C. 用 RikkaHub 的「测试连接」验证

设置 → 提供商 → 详情页左下角**插头图标** → 选模型 → 测试。
`Non-streaming`、`Streaming`、**`Tool Call`** 三项应全绿。
只有 Tool Call 失败就说明能力标记确实没生效。

---

## 模型能力实测（服务端侧，无需怀疑）

| 检查项 | 结果 |
|---|---|
| DeepSeek 官方 `/models` 返回的 ID | `deepseek-flash` ✅ 真实存在 |
| 直连 API 带 `tools` 参数 | ✅ `finish_reason: tool_calls`，正确返回工具名与参数 |
| models.dev 数据 | ✅ `tool_call=True` |

**模型本身 100% 支持工具调用**，问题纯粹在 RikkaHub 本地这条模型记录的能力标记。

---

## MCP 服务端状态

正常，无需改动：

| 项 | 结果 |
|---|---|
| MCP 握手 | ✅ 200 `termux-native-mcp` v0.15.0 |
| 工具数 | ✅ 84 |
| 鉴权 | ✅ 固定 token 200 / 错误 401 |
| 设备 `.39` / `.133` | ✅ 均 `wise` |

---

## 附带发现：手机 adb 掉线

排查过程中手机 `192.168.110.13:5555` 转为 `offline`，`adb connect` 超时。
无线调试在手机息屏/休眠时可能断开。建议：

1. 手机设置里保持「无线调试」开启
2. 在 Termux 里加 wakelock 避免被挂起：
   ```bash
   termux-wake-lock
   ```
3. 需要更稳的话，考虑用 USB 连接手机（adb over USB 不受休眠影响）

---

## 相关文档

| 文档 | 内容 |
|---|---|
| [快速开始](快速开始.md) | 命令与机制完整说明 |
| [设备接入](设备接入.md) | 设备识别与故障排查 |
| [迁移指南](迁移指南.md) | 换新手机部署 |
| [RikkaHub 接入](RikkaHub-接入.md) | RikkaHub 两层配置 |
| [RikkaHub 对话使用](RikkaHub-对话使用.md) | 实测提问示例 |
| [RikkaHub 工具调用排查](RikkaHub-工具调用排查.md) | 「模型未开启工具调用」根因 |
| [诊断记录](诊断记录-工具不可用.md) | 完整排查过程 |
