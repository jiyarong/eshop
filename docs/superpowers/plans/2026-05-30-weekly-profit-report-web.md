# 周利润报表 Web 版实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 新增只读「周利润报表」Web 页面，复用现有 WB/Ozon 利润归因服务展示 `WR:` Google Sheet 的核心查看内容。

**架构：** Rails 新增一个只读 controller 提供店铺列表和周利润报表 JSON；报表 controller 根据 `platform` 分派到 `Ec::WbProfitAttribution` 或 `Ec::OzonProfitAttribution`，并用 `Ec::WeeklyRate.resolve` 获取汇率。React 前端新增 `reports/weekly-profit` 页面，通过 axios 调用接口，展示筛选区、汇总、SKU 明细和未分摊费用。

**技术栈：** Rails 8 API、Minitest、React 19、TypeScript、Vite、Ant Design、axios。

---

## 文件结构

- 创建 `app/controllers/weekly_profit_reports_controller.rb`：周利润报表只读 API，包含 `accounts` 和 `show` 动作。
- 修改 `config/routes.rb`：增加 `weekly_profit_reports/accounts` 与 `weekly_profit_reports` 路由。
- 创建 `test/controllers/weekly_profit_reports_controller_test.rb`：覆盖参数校验、店铺列表、WB/Ozon 成功响应和汇率缺失。
- 创建 `frontend/src/services/reports/weeklyProfit.ts`：前端报表 API 类型和请求函数。
- 创建 `frontend/src/pages/reports/WeeklyProfitReportPage.tsx`：周利润报表页面。
- 修改 `frontend/src/router/index.tsx`：挂载 `/reports/weekly-profit`，默认首页跳转到报表页。
- 修改 `frontend/src/layouts/AppLayout.tsx`：顶部导航增加「报表」入口。

---

## 任务 1：后端路由与 Controller 测试

**文件：**
- 创建：`test/controllers/weekly_profit_reports_controller_test.rb`
- 修改：`config/routes.rb`

- [ ] **步骤 1：编写失败的 controller 测试**

创建 `test/controllers/weekly_profit_reports_controller_test.rb`：

```ruby
require "test_helper"

class WeeklyProfitReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @wb_account = RawWb::SellerAccount.create!(
      name: "WB Test Shop",
      api_token: "wb-token",
      is_active: true,
      company_type: "small"
    )

    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Ozon Test Shop",
      client_id: "ozon-client",
      api_key: "ozon-key",
      is_active: true
    )
  end

  test "accounts returns active wb and ozon shops" do
    get "/weekly_profit_reports/accounts"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "WB Test Shop", body.dig("data", "wb", 0, "name")
    assert_equal "Ozon Test Shop", body.dig("data", "ozon", 0, "name")
  end

  test "show requires platform account and dates" do
    get "/weekly_profit_reports"

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/platform/, body["message"])
  end

  test "show rejects unsupported platform" do
    get "/weekly_profit_reports", params: {
      platform: "amazon",
      account_id: @wb_account.id,
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/platform/, body["message"])
  end

  test "show returns 422 when weekly rate is missing" do
    Ec::WeeklyRate.stub(:resolve, nil) do
      get "/weekly_profit_reports", params: {
        platform: "wb",
        account_id: @wb_account.id,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/汇率/, body["message"])
  end
end
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
bin/rails test test/controllers/weekly_profit_reports_controller_test.rb
```

预期：失败，错误包含路由不存在或 `No route matches`。

- [ ] **步骤 3：添加最小路由**

修改 `config/routes.rb`，在 Google Sheets 路由后增加：

```ruby
  get "weekly_profit_reports/accounts" => "weekly_profit_reports#accounts"
  get "weekly_profit_reports"          => "weekly_profit_reports#show"
```

- [ ] **步骤 4：运行测试验证进入 controller 缺失失败**

运行：

```bash
bin/rails test test/controllers/weekly_profit_reports_controller_test.rb
```

预期：失败，错误包含 `uninitialized constant WeeklyProfitReportsController`。

- [ ] **步骤 5：Commit**

```bash
git add config/routes.rb test/controllers/weekly_profit_reports_controller_test.rb
git commit -m "test: 添加周利润报表接口测试"
```

---

## 任务 2：实现后端周利润报表 API

**文件：**
- 创建：`app/controllers/weekly_profit_reports_controller.rb`
- 修改：`test/controllers/weekly_profit_reports_controller_test.rb`

- [ ] **步骤 1：扩展成功响应测试**

在 `test/controllers/weekly_profit_reports_controller_test.rb` 末尾增加两个测试。使用 stub 避免测试依赖真实利润归因数据：

```ruby
  test "show returns wb weekly profit payload" do
    rate = Ec::WeeklyRate.new(
      week_start: Date.parse("2026-05-18"),
      rate_cny_rub: 10.93,
      rate_byn_rub: 26.41
    )

    service = Struct.new(:results, :unallocated, :summary).new(
      [{ nm_id: 123, vendor_code: "KJ-228", after_tax: 88.5 }],
      { "未归属费用" => 12.3 },
      { total_after_tax: 88.5, tax_regime: "usn" }
    )

    Ec::WeeklyRate.stub(:resolve, rate) do
      Ec::WbProfitAttribution.stub(:new, ->(**kwargs) {
        assert_equal @wb_account.id, kwargs[:account_id]
        assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
        assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
        assert_equal rate.rate_cny_rub, kwargs[:rate_cny_rub]
        assert_equal rate.rate_byn_rub, kwargs[:rate_byn_rub]
        service
      }) do
        service.stub(:call, service) do
          get "/weekly_profit_reports", params: {
            platform: "wb",
            account_id: @wb_account.id,
            from_date: "2026-05-18",
            to_date: "2026-05-24"
          }
        end
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "wb", body.dig("data", "platform")
    assert_equal "WB Test Shop", body.dig("data", "account", "name")
    assert_equal 88.5, body.dig("data", "summary", "total_after_tax")
    assert_equal 123, body.dig("data", "rows", 0, "nm_id")
    assert_equal 12.3, body.dig("data", "unallocated", "未归属费用")
  end

  test "show returns ozon weekly profit payload" do
    rate = Ec::WeeklyRate.new(
      week_start: Date.parse("2026-05-18"),
      rate_cny_rub: 10.93,
      rate_byn_rub: 26.41
    )

    service = Struct.new(:results, :unallocated, :summary).new(
      [{ ozon_sku_id: "111", sku_code: "KJ-228", after_tax_profit: 150.0 }],
      { total: -20.0, rows: [{ type_id: 96, type_name: "Fine", amount: -20.0 }] },
      { total_after_tax_profit: 150.0, sku_count: 1 }
    )

    Ec::WeeklyRate.stub(:resolve, rate) do
      Ec::OzonProfitAttribution.stub(:new, ->(**kwargs) {
        assert_equal @ozon_account.id, kwargs[:account_id]
        assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
        assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
        assert_equal 10.93, kwargs[:rate_cny_rub]
        service
      }) do
        service.stub(:call, service) do
          get "/weekly_profit_reports", params: {
            platform: "ozon",
            account_id: @ozon_account.id,
            from_date: "2026-05-18",
            to_date: "2026-05-24"
          }
        end
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "ozon", body.dig("data", "platform")
    assert_equal "Ozon Test Shop", body.dig("data", "account", "name")
    assert_equal 150.0, body.dig("data", "summary", "total_after_tax_profit")
    assert_equal "111", body.dig("data", "rows", 0, "ozon_sku_id")
    assert_equal(-20.0, body.dig("data", "unallocated", "total"))
  end
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
bin/rails test test/controllers/weekly_profit_reports_controller_test.rb
```

预期：失败，错误包含 controller 未实现。

- [ ] **步骤 3：实现最小 controller**

创建 `app/controllers/weekly_profit_reports_controller.rb`：

```ruby
class WeeklyProfitReportsController < ApplicationController
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ArgumentError, with: :render_bad_request

  def accounts
    render json: {
      success: true,
      data: {
        wb: RawWb::SellerAccount.where(is_active: true).order(:id).map { |a| { id: a.id, name: a.name } },
        ozon: RawOzon::SellerAccount.where(is_active: true).order(:id).map { |a| { id: a.id, name: a.company_name } }
      },
      message: "ok"
    }
  end

  def show
    platform = params.require(:platform).to_s
    account_id = Integer(params.require(:account_id))
    from_date = parse_date(params.require(:from_date))
    to_date = parse_date(params.require(:to_date))

    unless %w[wb ozon].include?(platform)
      return render json: { success: false, message: "unsupported platform: #{platform}" }, status: :bad_request
    end

    rate = Ec::WeeklyRate.resolve(from_date.beginning_of_week)
    unless rate
      return render json: { success: false, message: "当前周期没有汇率：#{from_date.beginning_of_week}" },
                    status: :unprocessable_entity
    end

    account = find_account!(platform, account_id)
    service = build_service(platform, account_id, from_date, to_date, rate).call

    render json: {
      success: true,
      data: {
        platform: platform,
        account: account_payload(platform, account),
        period: { from_date: from_date.to_s, to_date: to_date.to_s },
        rates: rate_payload(platform, rate),
        summary: service.summary,
        rows: service.results,
        unallocated: service.unallocated
      },
      message: "ok"
    }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, message: "店铺不存在或未启用" }, status: :not_found
  rescue ActionController::ParameterMissing, ArgumentError => e
    render_bad_request(e)
  rescue => e
    Rails.logger.error("[WeeklyProfitReports] #{e.class}: #{e.message}")
    render json: { success: false, message: e.message }, status: :internal_server_error
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    raise ArgumentError, "invalid date: #{value}"
  end

  def find_account!(platform, account_id)
    case platform
    when "wb"
      RawWb::SellerAccount.where(is_active: true).find(account_id)
    when "ozon"
      RawOzon::SellerAccount.where(is_active: true).find(account_id)
    end
  end

  def account_payload(platform, account)
    {
      id: account.id,
      name: platform == "wb" ? account.name : account.company_name
    }
  end

  def rate_payload(platform, rate)
    payload = { rate_cny_rub: rate.rate_cny_rub }
    payload[:rate_byn_rub] = rate.rate_byn_rub if platform == "wb"
    payload
  end

  def build_service(platform, account_id, from_date, to_date, rate)
    case platform
    when "wb"
      Ec::WbProfitAttribution.new(
        account_id: account_id,
        from_date: from_date,
        to_date: to_date,
        rate_cny_rub: rate.rate_cny_rub,
        rate_byn_rub: rate.rate_byn_rub
      )
    when "ozon"
      Ec::OzonProfitAttribution.new(
        account_id: account_id,
        from_date: from_date,
        to_date: to_date,
        rate_cny_rub: rate.rate_cny_rub
      )
    end
  end

  def render_bad_request(error)
    render json: { success: false, message: error.message }, status: :bad_request
  end
end
```

- [ ] **步骤 4：运行测试验证通过**

运行：

```bash
bin/rails test test/controllers/weekly_profit_reports_controller_test.rb
```

预期：全部通过。

- [ ] **步骤 5：Commit**

```bash
git add app/controllers/weekly_profit_reports_controller.rb test/controllers/weekly_profit_reports_controller_test.rb
git commit -m "feat: 添加周利润报表接口"
```

---

## 任务 3：前端报表 API 封装

**文件：**
- 创建：`frontend/src/services/reports/weeklyProfit.ts`

- [ ] **步骤 1：创建 API 类型与请求函数**

创建 `frontend/src/services/reports/weeklyProfit.ts`：

```typescript
import request from '../../utils/request'
import type { ApiResponse } from '../../utils/request'

export type WeeklyProfitPlatform = 'wb' | 'ozon'

export interface ReportAccount {
  id: number
  name: string
}

export interface WeeklyProfitAccounts {
  wb: ReportAccount[]
  ozon: ReportAccount[]
}

export interface WeeklyProfitParams {
  platform: WeeklyProfitPlatform
  account_id: number
  from_date: string
  to_date: string
}

export interface WeeklyProfitPayload {
  platform: WeeklyProfitPlatform
  account: ReportAccount
  period: {
    from_date: string
    to_date: string
  }
  rates: Record<string, number>
  summary: Record<string, unknown>
  rows: Record<string, unknown>[]
  unallocated: Record<string, unknown>
}

export function listWeeklyProfitAccounts() {
  return request.get<ApiResponse<WeeklyProfitAccounts>>('/weekly_profit_reports/accounts')
}

export function getWeeklyProfitReport(params: WeeklyProfitParams) {
  return request.get<ApiResponse<WeeklyProfitPayload>>('/weekly_profit_reports', { params })
}
```

- [ ] **步骤 2：运行前端构建验证类型**

运行：

```bash
cd frontend
pnpm build
```

预期：构建仍通过。

- [ ] **步骤 3：Commit**

```bash
git add frontend/src/services/reports/weeklyProfit.ts
git commit -m "feat: 添加周利润报表前端接口"
```

---

## 任务 4：实现周利润报表页面

**文件：**
- 创建：`frontend/src/pages/reports/WeeklyProfitReportPage.tsx`

- [ ] **步骤 1：创建页面组件**

创建 `frontend/src/pages/reports/WeeklyProfitReportPage.tsx`：

```tsx
import { useEffect, useMemo, useState } from 'react'
import { Alert, Button, Card, DatePicker, Empty, Form, Select, Space, Statistic, Table, Typography } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import {
  getWeeklyProfitReport,
  listWeeklyProfitAccounts,
  type ReportAccount,
  type WeeklyProfitAccounts,
  type WeeklyProfitPayload,
  type WeeklyProfitPlatform,
} from '../../services/reports/weeklyProfit'

const { RangePicker } = DatePicker
const { Title, Text } = Typography

const wbColumns = [
  'nm_id', 'vendor_code', 'region', 'sales_qty', 'return_qty', 'net_qty',
  'settlement', 'delivery', 'storage', 'ad', 'goods_cost', 'pre_tax', 'tax', 'after_tax',
]

const ozonColumns = [
  'ozon_sku_id', 'sku_code', 'sales_revenue', 'commission', 'delivery_charge', 'total_ad_cost',
  'order_count', 'net_sales_count', 'blr_count', 'export_count', 'goods_cost',
  'pre_tax_profit', 'after_tax_profit', 'after_tax_margin_pct',
]

const summaryLabels: Record<string, string> = {
  total_sales_qty: '销售件数',
  total_return_qty: '退货件数',
  total_net: '账面小计',
  total_goods_cost: '货物成本',
  total_pre_tax: '税前利润',
  total_tax: '税额',
  total_after_tax: '税后净利',
  unallocated_rows: '未分摊行数',
  sku_count: 'SKU 数',
  total_sales_revenue: '销售收入',
  total_orders: '订单数',
  total_returns: '退货数',
  total_ad: '广告费',
  total_after_tax_profit: '税后净利',
  unallocated_total: '未分摊合计',
}

const wbSummaryKeys = [
  'total_sales_qty', 'total_return_qty', 'total_net', 'total_goods_cost',
  'total_pre_tax', 'total_tax', 'total_after_tax', 'unallocated_rows',
]

const ozonSummaryKeys = [
  'sku_count', 'total_sales_revenue', 'total_orders', 'total_returns',
  'total_ad', 'total_goods_cost', 'total_after_tax_profit', 'unallocated_total',
]

function asText(value: unknown) {
  if (value === null || value === undefined || value === '') return '-'
  if (typeof value === 'number') return Number.isInteger(value) ? String(value) : value.toFixed(2)
  return String(value)
}

function buildColumns(keys: string[]): ColumnsType<Record<string, unknown>> {
  return keys.map((key) => ({
    title: key,
    dataIndex: key,
    key,
    ellipsis: true,
    render: asText,
  }))
}

function unallocatedRows(platform: WeeklyProfitPlatform, unallocated: Record<string, unknown>) {
  if (platform === 'ozon') {
    const rows = Array.isArray(unallocated.rows) ? unallocated.rows : []
    return rows as Record<string, unknown>[]
  }

  return Object.entries(unallocated).map(([name, amount]) => ({ name, amount }))
}

export default function WeeklyProfitReportPage() {
  const [form] = Form.useForm()
  const [accounts, setAccounts] = useState<WeeklyProfitAccounts>({ wb: [], ozon: [] })
  const [platform, setPlatform] = useState<WeeklyProfitPlatform>('wb')
  const [report, setReport] = useState<WeeklyProfitPayload | null>(null)
  const [loading, setLoading] = useState(false)
  const [accountLoading, setAccountLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setAccountLoading(true)
    listWeeklyProfitAccounts()
      .then((res) => {
        setAccounts(res.data.data)
      })
      .catch((err) => {
        setError(err?.response?.data?.message || err.message || '店铺列表加载失败')
      })
      .finally(() => setAccountLoading(false))
  }, [])

  const accountOptions = useMemo(() => {
    return accounts[platform].map((account: ReportAccount) => ({
      value: account.id,
      label: account.name,
    }))
  }, [accounts, platform])

  const summaryKeys = report?.platform === 'ozon' ? ozonSummaryKeys : wbSummaryKeys
  const detailColumns = buildColumns(report?.platform === 'ozon' ? ozonColumns : wbColumns)
  const unallocatedData = report ? unallocatedRows(report.platform, report.unallocated) : []
  const unallocatedColumns = report?.platform === 'ozon'
    ? buildColumns(['type_id', 'type_name', 'posting_number', 'amount'])
    : buildColumns(['name', 'amount'])

  const onFinish = async (values: {
    platform: WeeklyProfitPlatform
    account_id: number
    dates: [dayjs.Dayjs, dayjs.Dayjs]
  }) => {
    setLoading(true)
    setError(null)
    try {
      const res = await getWeeklyProfitReport({
        platform: values.platform,
        account_id: values.account_id,
        from_date: values.dates[0].format('YYYY-MM-DD'),
        to_date: values.dates[1].format('YYYY-MM-DD'),
      })
      setReport(res.data.data)
    } catch (err: any) {
      setReport(null)
      setError(err?.response?.data?.message || err.message || '报表加载失败')
    } finally {
      setLoading(false)
    }
  }

  return (
    <Space direction="vertical" size={16} style={{ width: '100%' }}>
      <Title level={3}>周利润报表</Title>

      <Card>
        <Form
          form={form}
          layout="inline"
          initialValues={{
            platform: 'wb',
            dates: [dayjs().startOf('week').subtract(7, 'day'), dayjs().startOf('week').subtract(1, 'day')],
          }}
          onFinish={onFinish}
        >
          <Form.Item name="platform" label="平台" rules={[{ required: true }]}>
            <Select
              style={{ width: 120 }}
              options={[
                { value: 'wb', label: 'WB' },
                { value: 'ozon', label: 'Ozon' },
              ]}
              onChange={(value: WeeklyProfitPlatform) => {
                setPlatform(value)
                form.setFieldsValue({ account_id: undefined })
              }}
            />
          </Form.Item>
          <Form.Item name="account_id" label="店铺" rules={[{ required: true, message: '请选择店铺' }]}>
            <Select
              loading={accountLoading}
              style={{ width: 220 }}
              options={accountOptions}
              placeholder="选择店铺"
            />
          </Form.Item>
          <Form.Item name="dates" label="周期" rules={[{ required: true, message: '请选择日期范围' }]}>
            <RangePicker />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" loading={loading}>
              查询
            </Button>
          </Form.Item>
        </Form>
      </Card>

      {error && <Alert type="error" message={error} showIcon />}

      {!report && !loading && !error && (
        <Card>
          <Empty description="请选择平台、店铺和周期后查询" />
        </Card>
      )}

      {report && (
        <>
          <Card>
            <Space direction="vertical" size={8} style={{ width: '100%' }}>
              <Text type="secondary">
                {report.account.name} · {report.period.from_date} ~ {report.period.to_date}
              </Text>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 16 }}>
                {summaryKeys.map((key) => (
                  <Statistic
                    key={key}
                    title={summaryLabels[key] || key}
                    value={asText(report.summary[key])}
                  />
                ))}
              </div>
            </Space>
          </Card>

          <Card title="SKU 明细">
            <Table
              rowKey={(_, index) => String(index)}
              loading={loading}
              dataSource={report.rows}
              columns={detailColumns}
              scroll={{ x: 'max-content' }}
              pagination={{ pageSize: 20 }}
            />
          </Card>

          <Card title="未分摊费用">
            <Table
              rowKey={(_, index) => String(index)}
              dataSource={unallocatedData}
              columns={unallocatedColumns}
              pagination={false}
              locale={{ emptyText: '无未分摊费用' }}
            />
          </Card>
        </>
      )}
    </Space>
  )
}
```

- [ ] **步骤 2：运行前端构建验证失败或通过**

运行：

```bash
cd frontend
pnpm build
```

预期：如果缺少 `dayjs` 类型或 Ant Design DatePicker 类型不匹配，按报错收窄类型；否则通过。

- [ ] **步骤 3：Commit**

```bash
git add frontend/src/pages/reports/WeeklyProfitReportPage.tsx
git commit -m "feat: 添加周利润报表页面"
```

---

## 任务 5：挂载前端路由和导航

**文件：**
- 修改：`frontend/src/router/index.tsx`
- 修改：`frontend/src/layouts/AppLayout.tsx`

- [ ] **步骤 1：挂载页面路由**

修改 `frontend/src/router/index.tsx`：

```tsx
import WeeklyProfitReportPage from '../pages/reports/WeeklyProfitReportPage'
```

将默认跳转改为：

```tsx
{ index: true, element: <Navigate to="/reports/weekly-profit" replace /> },
```

在 `children` 中增加：

```tsx
{ path: 'reports/weekly-profit', element: <WeeklyProfitReportPage /> },
```

- [ ] **步骤 2：新增导航入口**

修改 `frontend/src/layouts/AppLayout.tsx` 的 `items`，在 WB 菜单前增加：

```tsx
{
  key: '/reports/weekly-profit',
  label: '报表',
}
```

保留现有 WB 菜单，不删除已有入口。

- [ ] **步骤 3：运行前端构建验证通过**

运行：

```bash
cd frontend
pnpm build
```

预期：构建通过。

- [ ] **步骤 4：Commit**

```bash
git add frontend/src/router/index.tsx frontend/src/layouts/AppLayout.tsx
git commit -m "feat: 挂载周利润报表入口"
```

---

## 任务 6：端到端验证

**文件：**
- 不新增文件

- [ ] **步骤 1：运行后端测试**

运行：

```bash
bin/rails test test/controllers/weekly_profit_reports_controller_test.rb
```

预期：全部通过。

- [ ] **步骤 2：运行前端构建**

运行：

```bash
cd frontend
pnpm build
```

预期：构建通过。

- [ ] **步骤 3：启动 Rails 后端**

运行：

```bash
bin/rails server -p 4010
```

预期：服务监听 `http://127.0.0.1:4010`。

- [ ] **步骤 4：启动 Vite 前端**

运行：

```bash
cd frontend
pnpm dev -- --host 127.0.0.1
```

预期：Vite 输出本地访问地址，通常为 `http://127.0.0.1:5173/`。

- [ ] **步骤 5：浏览器手动验证**

打开 `http://127.0.0.1:5173/reports/weekly-profit`，验证：

- 页面展示平台、店铺、日期范围和查询按钮。
- 店铺下拉能加载活跃 WB/Ozon 店铺。
- 查询缺少汇率的周期时展示后端错误。
- 查询有汇率和数据的周期时展示汇总、SKU 明细和未分摊费用。

- [ ] **步骤 6：最终状态检查**

运行：

```bash
git status --short
```

预期：只包含本计划执行产生且已明确处理的文件变更；不要清理用户已有的无关改动。
