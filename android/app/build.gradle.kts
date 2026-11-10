import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is supplied by the local developer or CI process, never Git.
val signingStore = providers.environmentVariable("BOTTOGRAM_KEYSTORE_PATH").orNull
val signingPassword = providers.environmentVariable("BOTTOGRAM_KEYSTORE_PASSWORD").orNull
val signingAlias = providers.environmentVariable("BOTTOGRAM_KEY_ALIAS").orNull
val signingKeyPassword = providers.environmentVariable("BOTTOGRAM_KEY_PASSWORD").orNull
val signingInputs = listOf(signingStore, signingPassword, signingAlias, signingKeyPassword)
val signingConfigured = signingInputs.all { !it.isNullOrBlank() }
if (signingInputs.any { !it.isNullOrBlank() } && !signingConfigured) {
    throw GradleException("Supply all four BOTTOGRAM signing environment variables.")
}

android {
    namespace = "com.hayyaun.bottogram.bottogram"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hayyaun.bottogram.bottogram"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingConfigured) {
            create("release") {
                storeFile = file(signingStore!!)
                storeType = "PKCS12"
                storePassword = signingPassword
                keyAlias = signingAlias
                keyPassword = signingKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingConfigured) signingConfigs.getByName("release") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}
