import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("keystore/keystore.properties")
var hasReleaseKeystore = false
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    val storeFilePath = keystoreProperties.getProperty("storeFile")
    if (storeFilePath != null) {
        val storeFile = file(storeFilePath)
        hasReleaseKeystore = storeFile.exists()
    }
}

android {
    namespace = "com.epochtechlabs.viora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.epochtechlabs.viora"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 24
        versionName = "1.19.0"
    }

    // 🔥 Split APKs by ABI - each device downloads only what it needs
    // Play Store automatically generates separate APKs from your .aab upload
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true // Also build a universal APK for fallback
        }
    }

    signingConfigs {
        // Only create release signing config if keystore file exists
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                if (storeFilePath != null) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            // Use release signing for debug only if keystore exists (Google Play Billing testing)
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        release {
            // Use release keystore if available, otherwise fall back to debug signing
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            
            // Enable minification but disable resource shrinking (which causes the duplicate resource issue)
            isMinifyEnabled = true
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Same major line as purchases_flutter → purchases-hybrid-common (see Maven POM). Enables
    // [MainActivity] MethodChannel to use [SyncPurchasesCallback] — Flutter plugin’s
    // syncPurchases() does not surface errors to Dart.
    implementation("com.revenuecat.purchases:purchases:9.18.0")
    implementation("com.android.billingclient:billing:6.1.0")
    // App Check: debug token in debug builds; Play Integrity attestation in release
    debugImplementation("com.google.firebase:firebase-appcheck-debug")
    releaseImplementation("com.google.firebase:firebase-appcheck-playintegrity")    
    // Conflict resolution for transitive dependencies
    implementation("com.google.android.gms:play-services-basement:18.4.0")}

flutter {
    source = "../.."
}