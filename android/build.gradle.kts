// File: android/build.gradle.kts

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // --- PERBAIKAN ADA DI SINI ---
        // Classpath harus ada di dalam buildscript
        // Saya tambahkan juga gradle dan kotlin plugin agar aman
        classpath("com.android.tools.build:gradle:7.3.0") // Sesuaikan jika perlu
        // COBA TURUNKAN VERSI KOTLIN INI:
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0") 
        classpath("com.google.gms:google-services:4.3.15")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}