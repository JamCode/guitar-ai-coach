#!/bin/bash
# DeepCode 模型 & 难度切换脚本
# 修改 ~/.deepcode/settings.json 中的 model / thinkingEnabled / reasoningEffort

set -e

# ── help ──
show_help() {
  echo "DeepCode 模型 & 难度切换脚本"
  echo ""
  echo "用法:"
  echo "  $(basename "$0")              # 显示本帮助"
  echo "  $(basename "$0") --set        # 进入交互式配置"
  echo "  $(basename "$0") --help|-h    # 显示本帮助"
  echo ""
  echo "交互式修改 ~/.deepcode/settings.json 中的:"
  echo "  • env.MODEL             模型名（deepseek-v4-pro / deepseek-v4-flash / 自定义）"
  echo "  • thinkingEnabled       是否启用思考链（true / false）"
  echo "  • reasoningEffort       推理强度（low / medium / high）"
  echo ""
  echo "示例:"
  echo "  $(basename "$0") --set"
  echo "    进入交互菜单，依次选模型 → 思考链 → 推理强度"
  echo ""
  echo "  # 以下为等效的手动编辑（不通过脚本）："
  echo "  cat ~/.deepcode/settings.json"
  echo "  # 修改后重新打开 Deep Code 面板生效。"
  echo ""
  echo "改完后重新打开 Deep Code 面板生效。"
}

if [ "$#" -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  show_help
  exit 0
fi

if [ "$1" != "--set" ]; then
  echo "未知参数: $1"
  echo ""
  show_help
  exit 1
fi

SETTINGS="$HOME/.deepcode/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo '{"env":{}}' > "$SETTINGS"
fi

# ── 读取当前值 ──
current_model=$(python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
env = s.get('env', {})
print(env.get('MODEL', 'deepseek-v4-pro'))
" 2>/dev/null || echo "deepseek-v4-pro")

current_thinking=$(python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
print('true' if s.get('thinkingEnabled', True) else 'false')
" 2>/dev/null || echo "true")

current_effort=$(python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
print(s.get('reasoningEffort', 'medium'))
" 2>/dev/null || echo "medium")

# ── 选择模型 ──
echo "=== 当前配置 ==="
echo "模型:           $current_model"
echo "思考链 (thinkingEnabled):  $current_thinking"
echo "推理强度 (reasoningEffort): $current_effort"
echo ""

echo "=== 选择模型 ==="
echo "1) deepseek-v4-pro（默认，最完整）"
echo "2) deepseek-v4-flash（快速版，当前）"
echo "3) 输入自定义模型名"
read -p "请输入编号 [1-3] (默认 1): " model_choice

case "${model_choice:-1}" in
  1) new_model="deepseek-v4-pro" ;;
  2) new_model="deepseek-v4-flash" ;;
  3)
    read -p "输入模型名称: " custom_model
    new_model="${custom_model:-deepseek-v4-pro}"
    ;;
  *) new_model="deepseek-v4-pro" ;;
esac

# ── 是否启用思考链 ──
echo ""
echo "=== 思考链 (thinkingEnabled) ==="
echo "1) 开启 (true)"
echo "2) 关闭 (false)"
read -p "请输入编号 [1-2] (默认 1): " thinking_choice

case "${thinking_choice:-1}" in
  1) new_thinking=true ;;
  2) new_thinking=false ;;
  *) new_thinking=true ;;
esac

# ── 推理强度 ──
echo ""
echo "=== 推理强度 (reasoningEffort) ==="
echo "1) low   (快速响应，较少推理)"
echo "2) medium (平衡)"
echo "3) high  (深度推理，更慢但更全面)"
read -p "请输入编号 [1-3] (默认 2): " effort_choice

case "${effort_choice:-2}" in
  1) new_effort="low" ;;
  2) new_effort="medium" ;;
  3) new_effort="high" ;;
  *) new_effort="medium" ;;
esac

# ── 写入配置 ──
python3 -c "
import json

with open('$SETTINGS') as f:
    s = json.load(f)

if 'env' not in s:
    s['env'] = {}

s['env']['MODEL'] = '$new_model'
s['thinkingEnabled'] = $new_thinking
s['reasoningEffort'] = '$new_effort'

with open('$SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
" 2>&1

echo ""
echo "✅ 已更新配置！"
echo "模型:           $new_model"
echo "思考链:         $new_thinking"
echo "推理强度:       $new_effort"
echo ""
echo "请重新打开 Deep Code 面板 (Cmd+Shift+P → Deep Code: Open) 使新配置生效。"
