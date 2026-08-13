> **核验日期：2026-07-27。**  
> “中国 IP”不等于一定能访问所有中国服务：银行、政务、视频会员、支付及部分社交平台可能还会校验实名、账号归属、设备指纹或风控策略。

| 服务商 | 中国 IP 与类型 | 起步公开价（USD） | 协议 / 鉴权 | 比较适合 | 注意点与来源 |
|---|---|---:|---|---|---|
| **Bright Data** | 中国住宅、移动、ISP、数据中心；官网称可到城市/州/邮编级定位 | 住宅按量付费 **$8/GB**（当前网页有活动折扣） | SOCKS5（通过 Proxy Manager）；后台/API；住宅/移动网络可能需 KYC | 企业级数据采集、广告验证、要求特定城市的测试 | 中国节点覆盖与产品最多，但价格偏高、合规审核较严格。[中国节点](https://brightdata.com/locations/cn) · [住宅定价](https://brightdata.com/pricing/proxy-network/residential-proxies) |
| **Oxylabs** | 中国住宅及数据中心；官网列中国约 **925 万** IP | 5GB 起，**$6/GB**（$30/月） | HTTP(S)、HTTP/3、SOCKS5；支持粘性会话、IP 白名单 | 稳定性优先的研究、爬取及本地化网页测试 | 有目标站点限制（官网明确列举 Apple、银行、部分 Google 等）；高级筛选可能要 KYC。[中国节点](https://oxylabs.io/location-proxy/china) · [定价](https://oxylabs.io/pricing/residential-proxy-pool) |
| **Decodo**（原 Smartproxy） | 中国住宅、移动、ISP、数据中心 | 住宅 **$2/GB 起**；官网给中国专页，支持试用 | 平台/API；住宅代理通常支持轮换与定位 | 预算和规模之间的折中；市场研究、价格监测 | 先用试用实测目标城市和目标站的成功率；不同 IP 类型的计费不同。[中国节点](https://decodo.com/proxies/list/asia/china) |
| **SOAX** | 中国住宅、移动代理；官网显示约 **31,800** 个中国 IP，并列出中国移动/联通/电信等运营商 | 25GB **$3.60/GB**（$90/月） | HTTP(S)、SOCKS5、UDP、QUIC；用户名密码或 IP 白名单 | 需要运营商、城市、ISP 定向，以及轮换/粘性会话的业务 | 最低套餐相对较高；中国 IP 池数字低于头部大厂，具体城市库存需先在后台确认。[中国节点](https://soax.com/proxies/locations/china) · [住宅产品](https://soax.com/proxies/residential) · [定价](https://soax.com/pricing) |
| **IPRoyal** | 中国住宅约 **253 万** IP；另有 ISP、数据中心、移动产品 | 中国住宅 **$1.75/GB 起**；一般按量套餐 1GB 为 $7 | HTTP/HTTPS、SOCKS5、API；支持城市/省级、轮换和粘性会话 | 中小规模中国本地化测试、公开数据采集 | 流量“不过期”是优点；若需要固定中国 IP，应先确认 ISP/静态产品在目标城市有库存。[中国节点](https://iproyal.com/proxies-by-location/asia/china/) · [住宅定价](https://iproyal.com/pricing/residential-proxies/) |
| **Webshare** | 中国节点页显示约 **77 万**代理；有数据中心、静态住宅、轮换住宅 | 数据中心共享代理 **$2.99/月/100 IP 起**；轮换住宅 1GB **$3.50**（大量更低） | HTTP 与 SOCKS5；API、控制台，支持 IP 授权 | 低预算、浏览器代理、基础自动化和开发测试 | 低价中国静态/数据中心 IP 更容易被严格站点识别；页面有免费小套餐，可先验证出口 IP 归属。[中国节点](https://www.webshare.io/proxy-locations/cn) · [定价](https://www.webshare.io/pricing) |
| **Infatica** | 中国住宅 IP，官网列出上海、北京、广州、深圳、成都、重庆等城市 | 按量 **$4/GB**；有 **$4 / 7 天**试用 | SOCKS/HTTP；用户名密码或 IP 白名单；API；国家/城市/ISP 定向 | 要指定国内城市、且希望先小额测试的场景 | 官网虽列多个城市，但库存实时波动；小额试用后应检查 ASN、城市库和实际延迟。[中国节点](https://infatica.io/location/asia/china/) · [定价](https://infatica.io/pricing/) |
| **Proxy-Seller** | 住宅网络覆盖 220+ 地区，提供城市及 ISP 定向；需下单/后台确认中国库存 | 1GB **$3.50**；3GB **$9**；提供 **$1.99 / 3 天**试用 | 官网标明 HTTPS、SOCKS5；IP 授权、API；轮换或粘性会话 | 有短期任务、希望低成本试验轮换住宅代理 | 中国库存没有在产品页直接给出精确数量，购买前建议让客服书面确认目标城市、ASN 与是否能退款。[住宅产品/定价](https://proxy-seller.com/residential-proxies/) |
| **Geonode** | 中国专页称支持中国、任意州/城市；住宅支持国家定位和轮换/粘性模式 | 10GB 月付约 **$0.792/GB**；量大可低至 $0.27/GB | 官方示例使用用户名:密码代理端点；API；国家定位和会话模式 | 流量较大、成本优先的公开网页采集 | 极低单价主要在超大流量档；中国城市级实际可用量需要注册后验证，不建议直接按宣传单价作预算。[中国节点](https://geonode.com/proxies-by-location/china-proxy) · [住宅定价](https://geonode.com/products/residential-proxies) |
| **Proxy-Seller / Webshare 以外的备选：SOAX、Infatica 已足够** | — | — | — | — | 为避免把未能核实“中国大陆库存”的国际供应商混进列表，我没有列 NetNut、Rayobyte 等。它们有全球网络，但本次搜索结果中未拿到同等明确的中国节点官方佐证。 |

## 怎么选

- **只是偶尔从海外访问一个中国本地网站、看地区展示内容**：先选 **Webshare** 或 **IPRoyal** 的小套餐，成本低、可以先测。
- **必须是某个城市（如上海、北京、深圳）**：优先 **Bright Data、Oxylabs、Infatica、SOAX**；下单前要求客服或后台明确显示城市库存。
- **要固定会话 / 登录后测试自己有权限的业务系统**：选带 **粘性会话或静态 ISP** 的产品，如 IPRoyal、Oxylabs、Bright Data；不要频繁切换 IP。
- **公司级、大规模公开数据采集或广告验证**：Bright Data、Oxylabs、SOAX、Decodo 的产品体系和支持更完整，但要接受 KYC、用途审查和更高成本。
- **成本极敏感、流量很大**：Geonode、Webshare、Proxy-Seller 可比较，但先做目标站点成功率、延迟、城市/ASN 真实性测试。

## 下单前建议核对的 6 件事

1. **确认“China”是中国大陆，而不是香港、台湾或仅显示 CN 的误归属。** 用至少两个 IP 查询库交叉确认。
2. 说明你要的类型：
    - 普通浏览 / 数据抓取：**轮换住宅 IP**；
    - 稳定登录会话：**粘性住宅或静态 ISP IP**；
    - 高速且对风控不敏感：**数据中心 IP**。
3. 确认是否要求**城市、运营商（电信/联通/移动）或 ASN**；很多服务的“城市定位”不代表每个城市始终有库存。
4. 查清楚**鉴权方式**：用户名密码通常最方便；公司/服务器场景可用 IP 白名单。
5. 先买最低套餐或试用，分别测试：IP 定位、访问延迟、目标网站能否正常访问、连续会话是否稳定。
6. 遵守目标网站条款和所在地/中国相关法律；不要将代理用于绕过账号风控、规避制裁、欺诈或未经授权访问。