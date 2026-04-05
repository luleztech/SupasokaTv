import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ayubu.supasoka"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ayubu.supasoka"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val envFile = System.getenv("MYAPP_RELEASE_STORE_FILE")
            if (!envFile.isNullOrBlank()) {
                storeFile = file(envFile)
                storePassword = System.getenv("MYAPP_RELEASE_STORE_PASSWORD") ?: ""
                keyAlias = System.getenv("MYAPP_RELEASE_KEY_ALIAS") ?: ""
                keyPassword = System.getenv("MYAPP_RELEASE_KEY_PASSWORD") ?: ""
            } else if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                val sf = keystoreProperties.getProperty("storeFile")
                if (sf != null) {
                    storeFile = file(sf)
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystorePropertiesFile.exists() ||
                    !System.getenv("MYAPP_RELEASE_STORE_FILE").isNullOrBlank()
                ) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}
