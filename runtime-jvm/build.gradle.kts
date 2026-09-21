plugins {
    kotlin("jvm") version "2.4.20"
    `java-library`
}

group = "actor.starintel.starlang"
version = "0.1.0-SNAPSHOT"

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
    withSourcesJar()
}

kotlin {
    jvmToolchain(17)
}

val testSourceSet = sourceSets.named("test")

tasks.named<Test>("test") {
    // Acceptance is expressed as executable real-runtime smokes below rather
    // than framework-discovered JUnit tests.
    enabled = false
}


tasks.register<JavaExec>("runtimeSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.RuntimeSmokeKt")
}

tasks.register<JavaExec>("javaAbiSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.JavaAbiSmoke")
}

tasks.register<JavaExec>("wireDispatcherSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.WireDispatcherSmokeKt")
}

tasks.register<JavaExec>("supervisorSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.SupervisorSmokeKt")
}

tasks.register<JavaExec>("journalSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.JournalSmokeKt")
}

tasks.register<JavaExec>("heartbeatLeaseSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.HeartbeatLeaseSmokeKt")
}

tasks.register<JavaExec>("artifactVerificationSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.ArtifactVerificationSmokeKt")
}

tasks.register<JavaExec>("effectPortsSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.EffectPortsSmokeKt")
}

tasks.register<JavaExec>("canonicalProtocolSmoke") {
    dependsOn(tasks.named("testClasses"))
    classpath = testSourceSet.get().runtimeClasspath
    mainClass.set("actor.starintel.starlang.runtime.CanonicalProtocolSmokeKt")
}

tasks.named("check") {
    dependsOn(
        "runtimeSmoke",
        "javaAbiSmoke",
        "wireDispatcherSmoke",
        "supervisorSmoke",
        "journalSmoke",
        "heartbeatLeaseSmoke",
        "artifactVerificationSmoke",
        "effectPortsSmoke",
        "canonicalProtocolSmoke",
    )
}
