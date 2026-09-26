import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from CI secrets (KEYSTORE_B64 etc.); every release
// must use the same key or installed copies can't update.
val keystoreB64: String? = System.getenv("KEYSTORE_B64")
val releaseKeystore = keystoreB64?.takeIf { it.isNotBlank() }?.let {
    val f = layout.buildDirectory.file("release.p12").get().asFile
    f.parentFile.mkdirs()
    f.writeBytes(Base64.getMimeDecoder().decode(it))
    f
}

android {
    namespace = "com.freeb5d.kite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.freeb5d.kite"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storeType = "pkcs12"
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs.useLegacyPackaging = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Go core (link parsing, subscriptions, xray-core), built by CI with gomobile.
    implementation(files("libs/kitecore.aar"))
    implementation("androidx.core:core-ktx:1.15.0")
}

flutter {
    source = "../.."
}
