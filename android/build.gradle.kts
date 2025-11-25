import com.android.build.gradle.AppExtension
import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}


// === Fix for namespace and JVM target compatibility ===
subprojects {
    // For library modules (plugins that apply com.android.library)
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            // fallback namespace if not set by plugin
            if ((namespace == null) || namespace!!.isEmpty()) {
                // try using project.group, otherwise set a default
                namespace = if (project.group.toString().isNotEmpty()) project.group.toString() else "com.yourcompany.${project.name}"
            }
        }
    }

    // For application modules (plugins that apply com.android.application)
    plugins.withId("com.android.application") {
        extensions.configure<AppExtension> {
            if ((namespace == null) || namespace!!.isEmpty()) {
                namespace = if (project.group.toString().isNotEmpty()) project.group.toString() else "com.yourcompany.${project.name}"
            }
        }
    }
}

// Configure JVM target for all tasks after projects are evaluated
gradle.projectsEvaluated {
    subprojects {
        // Configure Kotlin compile options to ensure JVM target compatibility
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
            kotlinOptions {
                jvmTarget = JavaVersion.VERSION_11.toString()
            }
        }
        
        // Configure Java compile options to ensure JVM target compatibility
        // This will override any plugin-specific settings
        tasks.withType<org.gradle.api.tasks.compile.JavaCompile> {
            sourceCompatibility = JavaVersion.VERSION_11.toString()
            targetCompatibility = JavaVersion.VERSION_11.toString()
        }
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
