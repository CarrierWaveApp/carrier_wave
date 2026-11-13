import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing lives in the gitignored android/keystore.properties next to
// the (also gitignored) keystore. Machines without it still build debug fine;
// assembleRelease just produces an unsigned APK there.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "app.carrierwave.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.carrierwave.android"
        minSdk = 24
        targetSdk = 35
        versionCode = 14
        versionName = "0.7.1"
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (keystoreProperties.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        // BuildConfig.VERSION_NAME is passed as `program_version` into the
        // shared ADIF writer (AdifApi.exportActivation / exportBulk), matching
        // iOS's CFBundleShortVersionString.
        buildConfig = true
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/java")
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs.keepDebugSymbols.add("**/*.so")
    }
}

// Build the Rust core (.so per ABI) + regenerate UniFFI Kotlin bindings before
// compiling Kotlin. The artifacts (jniLibs/*.so, uniffi/cw_ffi/*.kt) are
// gitignored build output. Up-to-date checks key off the cw-core Rust sources.
val buildRustCore by tasks.registering(Exec::class) {
    workingDir = rootDir
    commandLine("bash", "${rootDir}/build-rust.sh")
    inputs.dir("${rootDir}/../rust/cw-core/cw-ffi/src")
    inputs.dir("${rootDir}/../rust/cw-core/cw-domain/src")
    inputs.dir("${rootDir}/../rust/cw-core/cw-store/src")
    inputs.dir("${rootDir}/../rust/cw-core/cw-net/src")
    inputs.dir("${rootDir}/../rust/cw-core/cw-sync/src")
    outputs.dir("${projectDir}/src/main/jniLibs")
    outputs.dir("${projectDir}/src/main/java/uniffi")
}

tasks.named("preBuild") {
    dependsOn(buildRustCore)
}

dependencies {
    // UniFFI-generated Kotlin bindings require JNA, pulled as an AAR so
    // jnidispatch.so is bundled into the APK.
    implementation("net.java.dev.jna:jna:5.15.0@aar")

    val composeBom = platform("androidx.compose:compose-bom:2025.05.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Satellite pass alerts: 6 h TLE refresh + alert replan worker.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    // Encrypted-at-rest key/value store backing the OAuth SecureStore (refresh
    // token + in-flight PKCE verifier), keyed by the Android Keystore.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // OpenStreetMap view for the club member map (no API key required).
    implementation("org.osmdroid:osmdroid-android:6.1.20")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    // Real org.json for local unit tests — android.jar's copy is stubbed.
    testImplementation("org.json:json:20240303")
}
