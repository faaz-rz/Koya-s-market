import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(propertyName: String, environmentName: String): String? =
    signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("storeFile", "KOYAS_ANDROID_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "KOYAS_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "KOYAS_ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "KOYAS_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

val flutterDartDefines = ((project.findProperty("dart-defines") as String?) ?: "")
    .split(',')
    .filter { it.isNotBlank() }
    .mapNotNull { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        }.getOrNull()
    }
    .mapNotNull { define ->
        val separator = define.indexOf('=')
        if (separator <= 0) null else define.substring(0, separator) to define.substring(separator + 1)
    }
    .toMap()

val isReleaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

val pushEnabled = flutterDartDefines["ENABLE_PUSH_NOTIFICATIONS"] == "true"
if (pushEnabled) {
    for (key in listOf("FIREBASE_PROJECT_ID", "FIREBASE_MESSAGING_SENDER_ID", "FIREBASE_ANDROID_API_KEY", "FIREBASE_ANDROID_APP_ID")) {
        if (flutterDartDefines[key].isNullOrBlank()) throw GradleException("Push configuration is missing: $key")
    }
}

if (isReleaseBuildRequested) {
    if (!hasReleaseSigning) {
        throw GradleException(
            "Release signing is required. Configure ignored key.properties or all KOYAS_ANDROID_* variables.",
        )
    }
    val supabaseUrl = flutterDartDefines["SUPABASE_URL"] ?: ""
    val supabaseAnonKey = flutterDartDefines["SUPABASE_ANON_KEY"] ?: ""
    val privacyPolicyUrl = flutterDartDefines["PRIVACY_POLICY_URL"] ?: ""
    val accountDeletionUrl = flutterDartDefines["ACCOUNT_DELETION_URL"] ?: ""
    val playReviewLoginEnabled =
        flutterDartDefines["ENABLE_PLAY_REVIEW_LOGIN"]?.equals("true", ignoreCase = true) == true
    if (!supabaseUrl.startsWith("https://") || supabaseAnonKey.isBlank()) {
        throw GradleException(
            "Release backend configuration is required. Pass HTTPS SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.",
        )
    }
    if (!privacyPolicyUrl.startsWith("https://") || !accountDeletionUrl.startsWith("https://")) {
        throw GradleException(
            "Release legal URLs are required. Pass HTTPS PRIVACY_POLICY_URL and ACCOUNT_DELETION_URL with --dart-define.",
        )
    }
    if (!playReviewLoginEnabled) {
        throw GradleException(
            "Reusable Google Play review access is required. Pass --dart-define=ENABLE_PLAY_REVIEW_LOGIN=true.",
        )
    }
}

android {
    namespace = "com.koyas.koyas_supermarket"
    buildFeatures {
        // AGP 9 disables generated resValue entries by default. Firebase needs
        // these native values when Android restarts its messaging service.
        resValues = pushEnabled
    }
    // Compile with the SDK required by encrypted-storage dependencies while
    // keeping the Play submission's runtime behavior target fixed at API 36.
    compileSdk = 37
    // Use the highest NDK requested by the native Flutter plugins.
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        if (pushEnabled) {
            resValue("string", "google_app_id", requireNotNull(flutterDartDefines["FIREBASE_ANDROID_APP_ID"]))
            resValue("string", "google_api_key", requireNotNull(flutterDartDefines["FIREBASE_ANDROID_API_KEY"]))
            resValue("string", "gcm_defaultSenderId", requireNotNull(flutterDartDefines["FIREBASE_MESSAGING_SENDER_ID"]))
            resValue("string", "project_id", requireNotNull(flutterDartDefines["FIREBASE_PROJECT_ID"]))
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // This application ID is the permanent Google Play identity. Do not
        // change it after the first Play Console artifact is uploaded.
        applicationId = "com.koyas.koyas_supermarket"
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(requireNotNull(releaseStorePath))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            // Never ship a release artifact signed with Flutter's shared debug key.
            // Configure signing through ignored key.properties or KOYAS_ANDROID_* env vars.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

 dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
