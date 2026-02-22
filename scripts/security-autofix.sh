#!/bin/bash
set -eu

trap 'echo "Error on line $LINENO"; exit 1' ERR

# Security auto-fix script for CodeQL alerts
# This script fixes common CodeQL security issues automatically

REPO="$1"
TOKEN="$2"
ALERTS_FILE="${3:-/tmp/alerts.json}"

FIXES_APPLIED=0
MODIFIED_FILES=""

echo "🔧 Processing security alerts from $ALERTS_FILE..."

if [[ ! -f "$ALERTS_FILE" ]]; then
  echo "❌ Alerts file not found: $ALERTS_FILE"
  exit 1
fi

ALERTS=$(cat "$ALERTS_FILE") || { echo "❌ Failed to read alerts file"; exit 1; }
echo "Loaded alerts: $(echo "$ALERTS" | jq -r 'length') total"

# Pattern 1: Fix code injection - Extract GitHub expressions to env vars
echo "🔧 Fixing code injection vulnerabilities..."

CODE_INJECTION_ALERTS=$(echo "$ALERTS" | jq '[.[] | select(.rule == "actions/code-injection/medium")]' 2>/dev/null || echo "[]")
CODE_INJECTION_COUNT=$(echo "$CODE_INJECTION_ALERTS" | jq 'length')
echo "Found $CODE_INJECTION_COUNT code-injection alerts"

FIXES_APPLIED=0
echo "$CODE_INJECTION_ALERTS" | jq -c '.[]' | while IFS= read -r alert_json; do
  [[ -z "$alert_json" ]] && continue
  
  file=$(echo "$alert_json" | jq -r '.file // empty')
  msg=$(echo "$alert_json" | jq -r '.message // empty')
  rule=$(echo "$alert_json" | jq -r '.rule // empty')
  
  [[ -z "$file" ]] || [[ ! -f "$file" ]] && continue
  [[ "$rule" != "actions/code-injection/medium" ]] && continue
  [[ -z "$msg" ]] && continue
  
  if [[ "$msg" =~ \$\{\{\s*([^}]+)\s*\}\} ]]; then
    var_expr="${BASH_REMATCH[1]}"
    # Trim spaces from captured expression
    var_expr=$(echo "$var_expr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    var_name="FIX_$(echo "$var_expr" | sed 's/[^a-zA-Z0-9_]/_/g' | tr '[:lower:]' '[:upper:]')"
    var_name="${var_name:0:32}"
    
    echo "  📝 Processing $file: $var_expr → $var_name"
    
    escaped_expr=$(printf '%s\n' "$var_expr" | sed 's/[&/\]/\\&/g' | sed 's/\[\|\]\|\.\|\*\|\^\|\$/\\&/g')
    sed -i "s/\${{ *$escaped_expr *}}/\$$var_name/g" "$file"
    
    # Find the line with our replacement
    linenum=$(grep -n "\$$var_name" "$file" | head -1 | cut -d: -f1)
    if [[ -n "$linenum" ]]; then
      # Search backwards from linenum to find the "run:" line that contains this variable
      runline=$(awk -v target="$linenum" 'NR < target && /^        run:/ {last=NR} END {print last}' "$file")
      
      if [[ -n "$runline" ]]; then
        # Insert env: before run:
        {
          head -n $((runline - 1)) "$file"
          echo "        env:"
          echo "          $var_name: \${{ $var_expr }}"
          tail -n +$runline "$file"
        } > "$file.tmp" && mv "$file.tmp" "$file"
      fi
    fi
    
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
    echo "  ✅ Fixed"
  fi
done

# Pattern 2: Fix unpinned actions
echo "🔧 Fixing unpinned actions..."

echo "$ALERTS" | jq -c '.[] | select(.rule == "actions/unpinned-tag")' | while IFS= read -r alert_json; do
  file=$(echo "$alert_json" | jq -r '.file // empty')
  rule=$(echo "$alert_json" | jq -r '.rule // empty')
  
  [[ ! -f "$file" ]] && continue
  [[ "$rule" != "actions/unpinned-tag" ]] && continue
  
  while IFS= read -r line_content; do
    if [[ "$line_content" =~ uses:\ ([^@]+)@(master|main|v[0-9]+)($|\ ) ]]; then
      action="${BASH_REMATCH[1]}"
      ref="${BASH_REMATCH[2]}"
      
      [[ "$action" == ./* ]] && continue
      [[ "$action" != */* ]] && continue
      
      owner=$(echo "$action" | cut -d/ -f1)
      repo=$(echo "$action" | cut -d/ -f2-)
      
      sha=$(GH_TOKEN="$TOKEN" gh api "repos/$owner/$repo/commits/$ref" --jq '.sha' 2>/dev/null | head -c 40)
      
      if [[ -n "$sha" && "$sha" =~ ^[0-9a-f]{40}$ ]]; then
        sed -i "s|uses: $action@$ref|uses: $action@$sha|g" "$file"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        echo "  ✅ Pinned $action@$ref → $sha"
      fi
    fi
  done < "$file"
done

echo "✓ Total fixes applied: $FIXES_APPLIED"
git diff --name-only 2>/dev/null || true
