#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
check_dir=$(mktemp -d /tmp/finlit-checks.XXXXXX)
common=(FinLit/Localization.swift FinLit/Models.swift FinLit/AIPrivacyPreferences.swift FinLit/CategoryReview.swift FinLit/LearnedCategoryRules.swift FinLit/Categorizer.swift)
client=(FinLit/AnonymousAIIdentity.swift FinLit/AssistantAnalytics.swift FinLit/OpenRouterCategorizer.swift)
compiler=(xcrun swiftc -parse-as-library -module-cache-path "$check_dir/cache")
cp -R FinLit/en.lproj FinLit/ru.lproj "$check_dir/"

"${compiler[@]}" "${common[@]}" Tests/CategorizationChecks.swift -o "$check_dir/categories"
"$check_dir/categories"
"${compiler[@]}" "${common[@]}" "${client[@]}" Tests/AssistantAnalyticsChecks.swift -o "$check_dir/analytics"
"$check_dir/analytics"
"${compiler[@]}" "${common[@]}" "${client[@]}" Tests/AIClientChecks.swift -o "$check_dir/client"
"$check_dir/client"
"${compiler[@]}" "${common[@]}" FinLit/AppearancePreferences.swift FinLit/BattleModels.swift FinLit/Storage.swift FinLit/Gamification.swift FinLit/Kaspi.swift Tests/CoreAuditChecks.swift -o "$check_dir/core"
"$check_dir/core"
"${compiler[@]}" "${common[@]}" FinLit/Kaspi.swift Tests/StatementParserChecks.swift -o "$check_dir/parser"
"$check_dir/parser"
"${compiler[@]}" "${common[@]}" FinLit/AppearancePreferences.swift FinLit/BattleModels.swift FinLit/Storage.swift FinLit/Gamification.swift Tests/LocalizationChecks.swift -o "$check_dir/localization"
"$check_dir/localization"
node --test Tests/category-policy.test.cjs Tests/category-audit.test.cjs Tests/api-validation.test.cjs Tests/chat-quota.test.cjs
node --check functions/category-audit.js
node --check functions/index.js
node --check openrouter-proxy/server.js
printf 'All checks passed. Temporary build files: %s\n' "$check_dir"
