# 部署 — Kamal 部署到正式环境

将当前分支部署到生产服务器（eshop.evexport.cn）。

**部署工具**：kamal  
**本地执行**（kamal 在本地 build Docker 镜像，push 到私有 registry，再 SSH 到服务器完成切换）

## 用法

`/部署` 或 `/deploy`

## 执行方式

通过 Bash 工具在本地执行：

```bash
cd /Users/jiyarong/Developer/5/eshop && bin/kamal deploy
```

## 规则

1. **只在明确要求时部署**：只有用户明确说"部署"时才执行，不得在 commit/push 后自动顺带部署。
2. **部署前确认**：展示当前 git 状态和最新 commit，询问用户确认后再部署。
3. **检查未提交变更**：若有未提交的修改，提醒用户先 commit。
4. **输出实时日志**：kamal 部署过程实时输出，失败时报告错误信息。

## 示例

`/部署`
→ 检查 git 状态 → 展示最新 commit → 确认后执行 `bin/kamal deploy`
