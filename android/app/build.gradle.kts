import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (Aisyah, DevOps): when the owner enrolls the Play
// keystore, CI materializes `android/key.properties` from the
// `release-signing` GitHub Environment secrets (docs/release-signing.md)
// and the release build signs with it. Without that file — local builds,
// PR CI, unenrolled tag builds — the debug key is used exactly as before,
// so behavior is unchanged until enrollment.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.mycontrolpanel.my_control_panel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (beta.1 background
        // alerting): its AAR metadata demands core library desugaring for
        // :app whenever the dependency is present. See
        // https://developer.android.com/studio/write/java8-support.html
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mycontrolpanel.my_control_panel"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 26 (Android 8.0): floor raised by sentry_flutter 10.x
        // (#26), whose native SDK declares minSdk 26. Was Flutter default.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Enrolled Play keystore (CI writes android/key.properties from the
        // `release-signing` environment). Absent locally -> unused.
        create("enrolled") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            keystoreProperties.getProperty("storeFile")?.let { storeFile = file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Enrolled keystore when present, debug key otherwise (local
            // builds, PR CI and unenrolled tag builds behave as before).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("enrolled")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Pairs with isCoreLibraryDesugaringEnabled above
    // (flutter_local_notifications, beta.1 background alerting).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
