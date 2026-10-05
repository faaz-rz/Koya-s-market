allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Flutter's integration_test plugin declares these dynamic ranges in
    // debug/profile builds. Pin those exact requests to stable releases within
    // their ranges so a QA build does not depend on Maven version-list queries.
    // Do not override explicit versions requested by any other dependency.
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            when ("${requested.group}:${requested.name}:${requested.version}") {
                "androidx.test:runner:1.2+" -> useVersion("1.2.0")
                "androidx.test:rules:1.2+" -> useVersion("1.2.0")
                "androidx.test.espresso:espresso-core:3.3+" -> useVersion("3.3.0")
            }
        }
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
