import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // android/app/google-services.json からFirebaseの設定を読み込む。
    // このファイルはAPIキーを含むためリポジトリには置かない（README「Firebaseの準備」参照）。
    // CIの結合テストはFirebaseエミュレータ専用のダミー（tool/ci/google-services.demo.json）を使う。
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// リリース署名鍵の設定。android/key.properties が存在すればそれを使う
// （ローカルでは手動作成、CIではワークフローがシークレットから生成する）。
// 無ければデバッグ署名にフォールバックし、`flutter run --release` を壊さない。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.github.kanerin.fuel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Play Storeでは com.example のような予約語を避ける必要があるため、
        // 最初から正式なIDにしておく（後から変えるとFirebaseへの再登録が要る）。
        applicationId = "io.github.kanerin.fuel"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // key.properties があれば本番署名、無ければデバッグ署名にフォールバック
            // （`flutter run --release` がローカルで壊れないようにするため）。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
