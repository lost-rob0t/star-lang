#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sbcl="${SBCL:-sbcl}"
kotlinc="${KOTLINC:-kotlinc}"
java="${JAVA:-java}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fixture="$repo_root/fixtures/actor-compiler/enrichment-worker.star"
generated="$work/EnrichmentWorkerStarActor.kt"
manifest="$work/manifest.json"
runner="$work/GeneratedActorSmoke.kt"

"$sbcl"   --script "$repo_root/starlang-cli/starlang-cli.lisp"   compile "$fixture"   --target kotlin   --output "$generated"   --manifest "$manifest"

grep -F 'object EnrichmentWorkerStarActor' "$generated" >/dev/null
grep -F '"wireVersion":1' "$manifest" >/dev/null

cat >"$runner" <<'EOF_RUNNER'
package actor.starintel.starlang.generated

import actor.starintel.starlang.runtime.ActorHandler
import actor.starintel.starlang.runtime.ActorTransition
import actor.starintel.starlang.runtime.PortableValue
import actor.starintel.starlang.runtime.StarRuntime

fun main() {
    val runtime = StarRuntime.create()
    val handlers = mapOf(
        "enrichment-worker-handler" to
            ActorHandler { message, _, _ ->
                ActorTransition(message)
            },
    )
    val actor = EnrichmentWorkerStarActor.register(runtime, handlers)
    val answer = runtime.ask(actor, PortableValue.Text("compiled"), 1)
    check(answer == PortableValue.Text("compiled")) {
        "generated actor returned $answer"
    }
    println("starlang generated Kotlin smoke: PASS")
}
EOF_RUNNER

main_sources=(
  "$repo_root"/runtime-jvm/src/main/kotlin/actor/starintel/starlang/runtime/*.kt
)

"$kotlinc"   "${main_sources[@]}"   "$generated"   "$runner"   -include-runtime   -d "$work/generated-actor-smoke.jar"

"$java" -jar "$work/generated-actor-smoke.jar"
