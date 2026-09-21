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

tasks.named("check") {
    dependsOn("runtimeSmoke", "javaAbiSmoke")
}
