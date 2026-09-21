#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kotlinc="${KOTLINC:-kotlinc}"
java="${JAVA:-java}"
javac="${JAVAC:-javac}"

if [[ -n "${KOTLIN_STDLIB:-}" ]]; then
  kotlin_stdlib="$KOTLIN_STDLIB"
else
  kotlinc_path="$(command -v "$kotlinc")"
  kotlin_home="$(cd "$(dirname "$kotlinc_path")/.." && pwd)"
  kotlin_stdlib="$kotlin_home/lib/kotlin-stdlib.jar"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

main_sources=(
  "$repo_root"/runtime-jvm/src/main/kotlin/actor/starintel/starlang/runtime/*.kt
)
runtime_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/RuntimeSmoke.kt"
wire_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/WireDispatcherSmoke.kt"
supervisor_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/SupervisorSmoke.kt"
journal_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/JournalSmoke.kt"
lease_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/HeartbeatLeaseSmoke.kt"
artifact_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/ArtifactVerificationSmoke.kt"
effect_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/EffectPortsSmoke.kt"
canonical_smoke="$repo_root/runtime-jvm/src/test/kotlin/actor/starintel/starlang/runtime/CanonicalProtocolSmoke.kt"
java_smoke="$repo_root/runtime-jvm/src/test/java/actor/starintel/starlang/runtime/JavaAbiSmoke.java"

"$kotlinc"   "${main_sources[@]}"   "$runtime_smoke"   -include-runtime   -d "$work/runtime-smoke.jar"

"$java" -jar "$work/runtime-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$wire_smoke" \
  -include-runtime \
  -d "$work/wire-smoke.jar"

"$java" -jar "$work/wire-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$supervisor_smoke" \
  -include-runtime \
  -d "$work/supervisor-smoke.jar"

"$java" -jar "$work/supervisor-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$journal_smoke" \
  -include-runtime \
  -d "$work/journal-smoke.jar"

"$java" -jar "$work/journal-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$lease_smoke" \
  -include-runtime \
  -d "$work/lease-smoke.jar"

"$java" -jar "$work/lease-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$artifact_smoke" \
  -include-runtime \
  -d "$work/artifact-smoke.jar"

"$java" -jar "$work/artifact-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$effect_smoke" \
  -include-runtime \
  -d "$work/effect-smoke.jar"

"$java" -jar "$work/effect-smoke.jar"

"$kotlinc" \
  "${main_sources[@]}" \
  "$canonical_smoke" \
  -include-runtime \
  -d "$work/canonical-smoke.jar"

"$java" -jar "$work/canonical-smoke.jar"

mkdir -p "$work/classes"
"$kotlinc" "${main_sources[@]}" -d "$work/classes"

"$javac"   -cp "$work/classes:$kotlin_stdlib"   -d "$work/classes"   "$java_smoke"

"$java"   -cp "$work/classes:$kotlin_stdlib"   actor.starintel.starlang.runtime.JavaAbiSmoke
