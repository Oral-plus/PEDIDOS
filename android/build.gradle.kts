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

// Suprimir avisos "source value 8 is obsolete" en todos los subproyectos (solo el warning, no se cambia Java)
gradle.projectsEvaluated {
    subprojects {
        tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
            if (!options.compilerArgs.contains("-Xlint:-options")) {
                options.compilerArgs.add("-Xlint:-options")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
