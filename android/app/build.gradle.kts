import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Apply the Google Services plugin only when the corresponding
// configuration file is present. Builds still succeed without Firebase
// while it is being provisioned; once android/app/google-services.json
// lands, the Firebase Messaging and App Check wiring activates.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.cluckrun.cluckrungame"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.cluckrun.cluckrungame"
        minSdk = 30
        targetSdk = 35
        // Version source-of-truth lives in pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Fall back to the existing release JKS if the new key.properties is
    // not present (keeps the previous CluckSprint release flow working).
    val legacyKeystore = file("cluckrun-release.jks")
    val hasLegacyKeystore = legacyKeystore.exists()

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        } else if (hasLegacyKeystore) {
            create("release") {
                storeFile = legacyKeystore
                storePassword = "cluckrun2024"
                keyAlias = "cluckrun"
                keyPassword = "cluckrun2024"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (hasKeystore || hasLegacyKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
