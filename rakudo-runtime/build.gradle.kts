import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Gradle build for rakudo's JVM runtime layer (package org.raku.rakudo),
// the sibling of nqp's Gradle build on its java-to-kotlin branch. The
// Makefile path (tools/templates/jvm/Makefile.in: javac --release 9 over
// src/vm/jvm/runtime/org/raku/rakudo/*.java into rakudo-runtime.jar)
// remains authoritative until parity is proven.
//
// Prerequisite: the nested nqp checkout's Gradle build must have produced
// its runtime jar set first (`cd ../nqp && ./gradlew buildJvm`); the
// compile classpath below is exactly that directory, mirroring the
// Makefile's $(BLD_NQP_JARS).

plugins {
    java
    kotlin("jvm") version "2.4.10"
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of((property("javaLanguageVersion") as String).toInt())
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_25
    }
}

repositories {
    mavenCentral()
}

val nqpRuntimeJars = layout.projectDirectory.dir("../nqp/build/jvm/share/runtime")

dependencies {
    implementation(fileTree(nqpRuntimeJars) { include("*.jar") })
}

sourceSets {
    main {
        java.setSrcDirs(listOf(layout.projectDirectory.dir("../src/vm/jvm/runtime")))
        kotlin.setSrcDirs(listOf(layout.projectDirectory.dir("../src/vm/jvm/runtime")))
        resources.setSrcDirs(emptyList<Any>())
    }
}

tasks.compileJava {
    // Flag set mirrors the Makefile rule (javac --release 9 -g:none
    // -encoding UTF8) except for the release level: nqp's runtime jars on
    // the java-to-kotlin branch are Java 25 class files, which javac
    // refuses on the classpath under --release 9 — so 25 is forced here,
    // matching nqp's modernized backend.
    options.release = 25
    options.encoding = "UTF8"
    options.isDebug = false
}

tasks.jar {
    archiveFileName = "rakudo-runtime.jar"
    // Mirrors `jar cf0` (store, no compression).
    entryCompression = ZipEntryCompression.STORED
}
