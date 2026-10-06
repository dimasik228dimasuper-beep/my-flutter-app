allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Только compileSdk=36. AarMetadata НЕ трогаем.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        try {
            android.javaClass
                .getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                .invoke(android, 36)
        } catch (_: Throwable) {
        }
        try {
            android.javaClass
                .getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(android, 36)
        } catch (_: Throwable) {
        }
        try {
            val m = android.javaClass.methods.firstOrNull {
                it.name == "compileSdkVersion" && it.parameterCount == 1
            }
            m?.invoke(android, 36)
        } catch (_: Throwable) {
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}