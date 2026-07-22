# SmartPack Calculator Function Skill

用于回答 WB & Ozon 物流包装、外箱装配、托盘装载、平台合规和 3D 装箱/装托可视化相关问题。本 Skill 是函数型测算 Skill，不是 SQL Skill。

## 适用问题

- 用户要根据单品尺寸和重量测算外箱尺寸、每箱装件数、托盘可装箱数、托盘可装件数。
- 用户要比较现有外箱方案和算法推荐方案。
- 用户问 Ozon 是否合规、WB 是否触发整托大件 / Mono-pallet。
- 用户要生成装箱、装托、托盘空隙或坐标轴 3D 图。

## 不支持范围

- 本 Skill 只支持单一 SKU / 单一种单品尺寸 / 单一外箱规格的包装和托盘测算。
- 不支持多种尺寸不一致的箱子混装托盘寻优。
- 不支持多个 SKU 混装、多个外箱规格混装、不同重量箱型混合排布。
- 如果用户提供多种尺寸或要求混装最优方案，必须明确告知：“SmartPack 当前只支持单种尺寸/单种外箱测算，不能按该 Skill 计算多箱型混装最优方案。”不要把多箱型拆开后假装得到一个混装最优结论。

## 强制原则

- 必须使用 Python 运行计算逻辑验算，不要只靠自然语言推导或心算。
- 缺少任何必需入参时，必须向用户列出缺少的字段并要求补充；不要猜测、不要套默认值，除非用户明确说“用工具默认值”。
- 如果输入包含多种单品尺寸、多个 SKU 或多种外箱尺寸，本 Skill 不适用；必须先提醒用户不支持混装寻优，只能分别对每一种尺寸单独测算。
- 默认行为必须贴近原网页工具未勾选“指定现实已有外箱尺寸”的状态：用户只说“最优”“推荐”“打托方案”“寻优”“测算”时，`use_fixed_box` 必须为 `false`。
- 即使通过 SKU 查到了系统维护的外箱尺寸、外箱重量和 PCS，也不要自动设置 `use_fixed_box=true`；这些字段只能作为“现有箱规对照”的可选信息。
- 只有用户明确说“按现有外箱”“现实外箱”“不改箱规”“对照现有箱”“用维护的外箱/PCS/外箱毛重”时，才设置 `use_fixed_box=true` 并传入 `fixed_*` 字段。
- 输出结果必须按原 SmartPack 工具口径：最多三个方案，包含方案 A/B/C、得分、外径、箱重、实装件数、阵列、Ozon/WB 标签、托盘统计、利用率、提示和 3D 图数据。
- `material` 当前在原工具中只保存和展示，不参与计算分支。不要自行发明“瓦楞纸箱可直接 SIOC”的分支；只有原算法进入 fallback 时才触发 SIOC。
- 如果用户要求可视化，必须生成 HTML，并引入 Three.js 展示 3D 坐标图；不要只描述图形。

## 函数接口

函数名：

```text
smart_pack_calculate(input) -> result
```

该函数一次只能接收一组单品尺寸和一组现有外箱尺寸。不要传数组型的多 SKU、多单品尺寸或多外箱规格。

## 模式选择

默认按算法推荐模式运行：

```json
{ "use_fixed_box": false }
```

这对应原网页工具里没有勾选“指定现实已有外箱尺寸（进入对照模式）”的状态。此模式只需要单品尺寸、单品重量、托盘限高、托盘限重和材质，输出的是算法推荐的外箱和托盘方案。

现有外箱对照模式只在用户明确要求时启用：

```json
{ "use_fixed_box": true }
```

此模式会把现有外箱固定为方案 A，并把算法推荐方案放在后面用于对比。注意：在该模式下，方案 A 只是“现有现实方案”，不一定是最优方案；回答用户“最优”时必须比较 `score`、`actualItems`、`actualBoxes`、`palletGross` 和平台标签，不能仅因为它是方案 A 就称它为最优。

如果用户给的是 SKU 编码：

- 先加载 `sku_dimensions` Skill 查询该 SKU 的单品/内箱尺寸、重量；这些字段用于 `length_cm`、`width_cm`、`height_cm`、`weight_kg`。
- 若用户没有明确要求按现有外箱，则即使查到了外箱长宽高、外箱重量、PCS，也必须保持 `use_fixed_box=false`。
- 若用户明确要求按现有外箱或对照现有箱规，则把外箱长宽高、PCS、外箱毛重映射到 `fixed_length_cm`、`fixed_width_cm`、`fixed_height_cm`、`fixed_pcs`、`fixed_gross_weight_kg`。

必需入参：

- `material`：`colorbox` 或 `corrugated`。当前只作为记录字段，不改变计算。
- `length_cm`：单品长 L，cm，必须 > 0。
- `width_cm`：单品宽 W，cm，必须 > 0。
- `height_cm`：单品高 H，cm，必须 > 0。
- `weight_kg`：单品毛重，kg，必须 > 0。
- `pallet_limit_height_cm`：托盘限界高度，cm，必须 > 0。
- `pallet_limit_weight_kg`：托盘限界承重，kg，必须 > 0。
- `use_fixed_box`：是否指定现有外箱，布尔值。

当 `use_fixed_box = true` 时还必须提供：

- `fixed_length_cm`：现有外箱长，cm。
- `fixed_width_cm`：现有外箱宽，cm。
- `fixed_height_cm`：现有外箱高，cm。
- `fixed_pcs`：该箱实装件数。
- `fixed_gross_weight_kg`：该箱总毛重，kg。

如果任一字段缺失，回复用户：

```text
无法测算，缺少以下入参：...
请补充后我再按 SmartPack 口径用 Python 复算。
```

## Python 校验

优先使用同目录的参考实现：

```bash
python3 docs/erp_ai_sql_query_agent_system_prompt/smart_pack_calculator/smart_pack_reference.py <<'JSON'
{
  "material": "colorbox",
  "length_cm": 38,
  "width_cm": 32,
  "height_cm": 15,
  "weight_kg": 2.5,
  "pallet_limit_height_cm": 180,
  "pallet_limit_weight_kg": 350,
  "use_fixed_box": false
}
JSON
```

如果运行环境不能访问该文件，必须在 Python 中复写相同逻辑后运行。不要用 SQL、Excel 或口头估算替代 Python 验算。

## 核心算法口径

基础常量：

- 欧标托盘底面：`120 x 80 cm`。
- 木托高度：`14.5 cm`。
- 算法生成外箱时使用净高上限：`165.5 cm`。
- 托盘总重含木托：`15 kg + 外箱数 * 单箱毛重`。

基础拦截：

- 若 `max(length,width,height) > 120` 或 `length + width + height > 200`，返回 `alert_limit`，不继续生成方案。
- WB 单品大件标记：`maxEdge > 80` 或 `sumEdge > 160`。

平台标签：

- 外箱先规范为 `box_x >= box_y`，`box_z` 为高度。
- Ozon 合规：`box_x <= 120 AND box_y <= 60 AND box_z <= 50`。
- WB Mono：`WB 单品大件` 或 `box_x > 80` 或 `box_x + box_y + box_z > 160`。
- 如果 WB Mono 为真，托盘计算限界强制使用 `min(用户限高, 180)` 和 `min(用户限重, 350)`。

现有外箱模式：

- 校验 `单品体积 * fixed_pcs <= 现有外箱体积`，否则 `alert_vol`。
- 校验 `fixed_gross_weight_kg <= 350`，否则 `alert_overw`。
- 尝试用 6 种单品朝向反推现有外箱内的 `nx * ny * nz = fixed_pcs`。
- 如果无法反推阵列，方案仍可计算，但标记为 `isIrregular = true`，矩阵显示为“混沌排列”。
- 现有外箱方案固定作为方案 A；算法推荐方案只取剩余最优 2 个。

算法推荐模式：

- 遍历单品 6 种朝向。
- 遍历 `i, j, k` 作为外箱内单品阵列。
- 跳过 `totalItems == 1`。
- 若 `totalItems <= 4` 且 `totalItems * weight_kg < 5`，跳过。
- 若单箱毛重 `totalItems * weight_kg > 25`，跳过。
- 外箱外径：
  - `box_x = ceil(i * dX + 1.5 + 0.5 + i * 0.2)`
  - `box_y = ceil(j * dY + 1.5 + 0.5 + j * 0.2)`
  - `box_z = ceil(k * dZ + 1.5 + 0.5 + k * 0.2)`
- 若 `box_x < box_y`，交换 X/Y 尺寸和 X/Y 阵列。
- 跳过 `box_x > 120 OR box_y > 120 OR box_z > 80`。
- 按外箱三边去重。
- 如果存在 Ozon 合规且非 WB Mono 的方案，只保留这些合规方案；否则保留全部候选。
- 按总分降序取前三个方案。

托盘启发式：

- 对外箱 6 种朝向分别尝试主干阵列 `core`。
- 主干区域按 `floor(120 / dx) * floor(80 / dy) * floor((limitH - 14.5) / dz)` 计算。
- 再尝试 `sideX`、`sideY` 填补侧边空间。
- 顶部 `top` 区使用 80% 支撑规则：`topMaxW = min(120, coreW / 0.8)`，`topMaxD = min(80, coreD / 0.8)`。
- 如果侧边块高于主干高度，对应方向顶部支撑范围收回到主干尺寸。
- 最后按承重截断：`maxBoxesByWeight = floor((limitW - 15) / gross)`。
- 选择外箱数最多的托盘布局。

评分：

- `s1` 托盘空间利用率，满分 35。
- `s2` 外箱内部利用率，满分 25。
- `s3` 装托稳定性，满分 15：底面积、顶部悬空、安全重心。
- `s4` 外箱合理性，满分 15：箱重区间和长短边比例。
- `s5` 装配复杂度，满分 10：分区数和朝向数量。
- 平台超规扣分：如果非 Ozon 合规或 WB Mono，扣 20。
- 最终得分：`max(0, s1 + s2 + s3 + s4 + s5 - penalty)`。

SIOC fallback：

- 只有在没有现有外箱方案且没有任何算法推荐外箱方案时触发。
- SIOC 使用单品尺寸作为外箱尺寸，仍做托盘阵列、得分和平台标签。
- 若 SIOC 也无法装载，返回 `alert_reject`。

## 输出格式

普通结果按以下结构汇报：

```text
SmartPack Python 校验完成。

方案 A：...
- 类型：综合最优解 / 现有现实方案 / 算法对比寻优 / SIOC 原箱直发
- 外径：L x W x H cm
- 箱重：... kg
- 实装：... 件/箱
- 阵列：nx x ny x nz，或 混沌排列
- 得分：... / 100
- Ozon：合规 / 大件费风险
- WB：标准件 / 整托大件
- 托盘：... 箱，... 件，... kg / 限重 ... kg，高 ... cm / 限高 ... cm
- 空间体积利用率：...%
- 底盘投影覆盖率：... cm² (...%)
- 提示：...
- 五维评分：s1/s2/s3/s4/s5/penalty
```

错误结果按工具 alert 口径输出：

- `alert_limit`：商品单品尺寸已违反基础物流红线。
- `alert_vol`：指定外箱容积小于商品总体积，装不下。
- `alert_overw`：现有外箱单重超 350kg。
- `alert_reject`：产品已完全击穿物流边界，拒绝装载。

## 3D HTML 可视化要求

当用户要求“画图”“3D”“坐标图”“可视化”“展示装箱/装托”时：

- 必须优先使用同目录模板 `smart_pack_visualization_template.html` 生成 HTML，不要临时自由发挥编写另一套 Three.js 页面。
- 生成方式：复制模板全文，把模板中的 `__SMART_PACK_RESULT_JSON__` 替换为 Python 校验得到的完整 JSON 结果；不要只替换 `plans[0]`，要保留全部 `plans` 供模板切换方案。
- 替换后的 JSON 必须是原始 JSON 对象文本，不要包 Markdown 代码块，不要转成字符串，不要删减 `palletBlocks`、`scores`、`actPadX/Y/Z`、`dimX/Y/Z` 等字段。
- 生成后的 HTML 应可直接打开。如果运行环境能写文件，输出一个 `.html` 文件；如果只能回答文本，输出完整 HTML。
- 如果模板文件不可访问，才允许手写 HTML；手写时必须完全遵守下面的坐标系、相机和绘制规则。
- 模板已经引入 Three.js：

```html
<script src="https://cdn.jsdelivr.net/npm/three@0.128.0/build/three.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js"></script>
```

- HTML 必须使用 Python 校验结果里的具体 `plans[0].palletBlocks`、外箱尺寸、内箱阵列和余量数据，不要重新手写另一套计算。
- 至少画两块区域：
  - 外箱剖视：外箱线框、内部单品阵列、X/Y/Z 轴和尺寸标签。
  - 托盘视图：120 x 80 x 14.5 木托、红色限高框、core/side/top 外箱块、剩余 X/Y/Z 空间。
- 坐标轴口径：X=长，Y=宽，Z=高，单位 cm。
- Three.js 坐标系和相机必须参考原 HTML 工具实现：
  - 初始化时设置 `THREE.Object3D.DefaultUp.set(0, 0, 1)`，让 Z 轴为垂直高度轴。
  - 场景对象坐标以左下底角为原点，盒子几何体用 `new THREE.BoxGeometry(w, h, d).translate(w / 2, h / 2, d / 2)`，再通过 `mesh.position.set(x, y, z)` 放置。
  - 不要使用 Three.js 默认的 Y-up 口径，不要把高度画到 Y 轴。
  - 轴颜色按原工具：X 红色 `#e53935`，Y 绿色 `#43a047`，Z 蓝色 `#1976d2`。
  - 外箱视图调用 `buildCoordinateAxes(cfg.box_x, cfg.box_y, cfg.box_z, false, axisDesc)`。
  - 托盘视图调用 `buildCoordinateAxes(120, 80, cfg.limitH, true, {x, y, z})`，木托从 `z=0` 到 `z=14.5`，货物从 `palletBlocks[*].z` 开始。
- 相机和视图切换必须参考原 HTML 工具：
  - 同时创建 `PerspectiveCamera(45, width / height, 1, 3000)` 和 `OrthographicCamera(-1, 1, 1, -1, 1, 3000)`。
  - 3D 视图使用透视相机，位置为 `camera.position.set(maxDim * 1.5, maxDim * 1.5, maxDim * 1.2)`，`OrbitControls.target` 指向模型包围盒中心，并允许旋转。
  - Top/XY 正交视图：相机位置 `center.x, center.y, center.z + maxDim * 2`，`up=(0,1,0)`。
  - Front/XZ 正交视图：相机位置 `center.x, center.y - maxDim * 2, center.z`，`up=(0,0,1)`。
  - Right/YZ 正交视图：相机位置 `center.x + maxDim * 2, center.y, center.z`，`up=(0,0,1)`。
  - 正交视图的 frustum 参考原工具：`frustumSize = maxDim * 1.5`，按容器宽高比设置 left/right/top/bottom。
- 内箱剖视摆放参考原工具：
  - 外箱半透明绘制为 `box_x × box_y × box_z`。
  - 若不是 SIOC 且不是混沌排列，内件从余量的一半开始：`sX = actPadX / 2`、`sY = actPadY / 2`、`sZ = actPadZ / 2`。
  - 内件坐标：`x = sX + ix * dimX`，`y = sY + iy * dimY`，`z = sZ + iz * dimZ`。
- 托盘视图摆放参考原工具：
  - 木托：`createSolidMeshBox(120, 80, 14.5)` 放在 `(0,0,0)`。
  - 限高框：`createPureWireframeBox(120, 80, limitH - 14.5)` 放在 `(0,0,14.5)`。
  - 每个 `palletBlocks` 按 `blk.x + x * blk.dx`、`blk.y + y * blk.dy`、`blk.z + z * blk.dz` 放置，循环数量不得超过 `blk.count`。
  - 剩余空间按原工具拆成 X/Y/Z 余量框，不要改变坐标口径。
- 鼠标悬停或标签应能看到块类型、坐标范围、尺寸、数量。

## 与其他 Skill 配合

- 如果用户给的是 SKU 编码而不是尺寸，先加载 `sku_dimensions` Skill 查询或要求补充尺寸、重量、pcs。
- 如果用户问库存体积或补货再装托，先加载 `inventory_procurement` Skill 获取库存数量，再用本 Skill 做包装/托盘测算。
- 本 Skill 不负责成本、利润、汇率和销售归因。
