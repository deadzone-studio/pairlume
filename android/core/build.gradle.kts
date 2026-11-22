// The part without Android: the link and pairing, so it can be tested against the real pairlumed on a computer.
plugins { id("org.jetbrains.kotlin.jvm") }

kotlin { jvmToolchain(21); compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

dependencies {
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // the interop tests need the Rust side: cargo build
    inputs.files(rootDir.parentFile.resolve("target/debug/pairlumed")).optional()
    outputs.upToDateWhen { false }
    testLogging { events("passed", "failed", "skipped"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
