# 托盘打包计算器

独立入口 `/reports/pallet_calculator`，沿用报表查看权限和 SKU 工作台的 SKU 可见范围。当前仅实现手动模式，不生成供货单、不保存包装修改、不调用平台 API。

- 选择平台、供货类型与 1～5 个 SKU（SPU 按展开后的 SKU 数量计数）。
- 全部箱数留空：推荐每个所选 SKU 的装载量，必要时分托；全部填写：按指定数量安排整批托盘。部分填写会明确报错，不截断或默默修改数量。
- 默认读取 `Ec::SkuDimension` 的外箱尺寸（cm）、外箱毛重、每外箱件数和内包装体积。缺失数据需要手动补充；单品体积缺失时可以排托，相关费用标记为未完成。
- 初始不超边、不侧放/立放；运营可以在平台允许范围内调整。托盘自重默认估算 25 kg，可按实测修改。WB 与 Ozon FBS 用含托毛重，Ozon FBO 按货物限重。
- 支持 Ozon FBO、Ozon FBS 可分拣信任收货、WB FBW 单一托盘和按件托盘；WB FBS 与自动选品/补货模式尚未实现。

## 计算与结果

`PalletPacking::Calculator` 是不读写数据库的服务。比较沿托盘长边、宽边的 SKU 条带分区，按允许朝向排列同 SKU 的完整支撑列。同一层可以拼接平面旋转 90° 的箱子（例如 50×30 cm 箱在 120×80 cm 底面可从规则网格的 4 箱提升为 6 箱）；每层重复同样的位置，确保完整支撑。搜索同时保留装载量大的候选和占用宽度小的候选，优先覆盖 SKU，再提高外箱装载体积。同托最多一个供货单、一个 SKU 对应一个商品条码。WB 同托最多 3 个条码。

这是稳定分区方案的启发式推荐，不是任意三维混排的全局最优证明，也不验证纸箱承压、易碎性或特殊品类资格。每次最多计算 100 托；超过后要求拆批，避免返回不完整方案。几何图每区最多展示 400 箱，数量表与交付说明保留完整数量。WB 单一托盘不足 50 cm 会给出必须调整的提示，不通过增减申报数量来掩盖。

`PalletPacking::Fees` 按商品数量和单品体积计算费用：

- Ozon FBO：每托 `max(ceil(商品总体积), 1900) × 路线价 × (1 − 折扣)`，不会用托盘外形体积代替商品体积。取货处理按 `ceil(商品体积) × 1.55`，出车费单独填写。排序费用按商品件数，支持同库区组成排序、跨库区排序和组成纠正。Fashion 免组成排序由运营确认活动资格后勾选。
- Ozon FBS：`外箱数 × 每箱件数 × 每件处理费`，不把外箱数当商品件数。默认每件 10 ₽，СЦ 自助收货可手填 0，特殊点位按实际报价。
- WB：当前 СЦ/PФЦ 入库免费；单一托盘按托/天仓储，按件托盘按商品升数/天仓储。未使用历史 500 ₽/托或 1.7 ₽/L 处理价。
- 固定费用整批仅计一次。处理费归属对应 SKU，共同费用按商品体积（缺失时暂按外箱体积）分摊，分摊结果之和等于已知费用小计。
- 路线报价默认为空，缺失数据不补 0。未算出的费用单列，完整总价为空，页面展示已知费用小计。免费期需从计费仓储天数中扣除。

规则口径来自 `/Users/xyy/ai/ozon_wb_docs/wildberries-ozon-pallet-rules-zh.md`（2026-10-14），参考交互来自 `/Users/xyy/Downloads/pallet-calculator.html`。当前参数不是实时仓库报价；2026-10-30 及后续费率需按后台重新核对，未引入未来费率。

## 实现入口

- `GET /reports/pallet_calculator(.json)`：页面/可见 SKU 包装目录与规则参数。
- `POST /reports/pallet_calculator/calculate(.json)`：纯计算，HTML 返回结果 Turbo Frame，JSON 返回同一结果数据。
- `app/controllers/reports/pallet_calculators_controller.rb`：只读 SKU 查询与参数入口。
- `app/services/pallet_packing/{rules,calculator,fees}.rb`：规则、排托与费用。
- `app/views/reports/pallet_calculators/`：表单、结果、SVG。
- `app/javascript/controllers/pallet_calculator_controller.js`：复用共享 SKU/SPU 选择器，保留当前会话内包装编辑，防抖重算并取消过期请求。
- 复制交付说明复用已有 `clipboard` Stimulus controller；表格使用 `table_viewport`。
- 所有文案位于 `config/locales/pallet_calculator*.yml`，覆盖中、英、俄。

## 验证

```sh
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bin/rails test test/services/pallet_packing/calculator_test.rb test/controllers/reports/pallet_calculators_controller_test.rb
node --check app/javascript/controllers/pallet_calculator_controller.js
```

不需要迁移；开发验证不启动 Web server，不运行前端构建，不调用平台 API。

当前验证结果：托盘计算器与既有 Ozon 路线费率相关回归 26 个测试、441 项断言通过，JS 语法检查通过。扩展的尺寸维护测试中，`index filters sku dimensions by responsible users` 仍使用旧 `Ec::SkuProductOperator` 测试数据，而筛选已读取 `Ec::SkuOperatorAssignment`，该无关失败保持原样。

本地 development 数据在数据库只读事务内测量（关闭 query cache）：选择 BB001-BK、BB001-BN、BB001-CF、BB002-BK、BB002-CF 的有效外箱记录，预加载为 1 次未缓存 SQL，最大 SQL 2028 bytes，ActiveRecord instantiation 事件报告 5 条记录。每 SKU 指定 20 箱、路线价示例 8 ₽/L：1 SKU 计算约 3.58 ms，2 托/20 箱/500 件；5 SKU 计算约 14.48 ms，10 托/100 箱/2300 件。时间仅包含纯计算服务，查询统计仅覆盖本次 SKU/包装预加载，不包含整页 HTTP、权限及 HTML/SVG 渲染，也不是平台真实报价验证。
