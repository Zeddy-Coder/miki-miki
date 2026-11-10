plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mikimiki.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Ідентифікатор застосунку Miki Miki (змінення робить Android «новим» застосунком)
        applicationId = "com.mikimiki.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Лише 64-бітні телефони (Pixel 8 Pro тощо): без зайвих libmpv для інших архітектур
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // libmpv для інших архітектур лежить усередині jar-файлів плагіна — виключаємо їх вручну
    packaging {
        resources {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
