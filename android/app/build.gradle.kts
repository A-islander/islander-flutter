import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing material lives beside the Flutter checkout, never inside it.
// Override the directory for another machine/CI with ISLANDER_SIGNING_DIR
// or -PislanderSigningDir=/absolute/private/path.
val signingDirectory = rootProject.file(
    providers.gradleProperty("islanderSigningDir")
        .orElse(providers.environmentVariable("ISLANDER_SIGNING_DIR"))
        .getOrElse("../../.signing/android")
).canonicalFile
val checkoutDirectory = rootProject.projectDir.parentFile.canonicalFile.toPath()
require(!signingDirectory.toPath().startsWith(checkoutDirectory)) {
    "Signing directory must be outside the Flutter checkout."
}

fun readSigningProperties(name: String): Properties = Properties().apply {
    val config = signingDirectory.resolve(name)
    if (config.isFile) config.inputStream().use { load(it) }
}

fun signingStore(properties: Properties): File? =
    properties.getProperty("storeFile")?.takeIf { it.isNotBlank() }?.let { value ->
        val candidate = File(value)
        (if (candidate.isAbsolute) candidate else signingDirectory.resolve(value)).canonicalFile
    }

val releaseSigningProperties = readSigningProperties("key.properties")
val debugSigningProperties = readSigningProperties("debug.properties")

fun verifySigning(label: String, configName: String, properties: Properties) {
    val config = signingDirectory.resolve(configName).canonicalFile
    check(config.isFile && !config.toPath().startsWith(checkoutDirectory)) {
        "Missing external $label signing configuration: $configName. Configure ISLANDER_SIGNING_DIR; no fallback key is used."
    }
    for (field in listOf("storeFile", "storeType", "keyAlias", "storePassword", "keyPassword")) {
        check(!properties.getProperty(field).isNullOrBlank()) {
            "Missing $field in external $label signing configuration."
        }
    }
    val store = signingStore(properties)!!
    check(store.isFile && !store.toPath().startsWith(checkoutDirectory)) {
        "$label keystore must exist outside the Flutter checkout; it will not be generated automatically."
    }
    val certificate = try {
        val keyStore = KeyStore.getInstance(properties.getProperty("storeType"))
        store.inputStream().use { keyStore.load(it, properties.getProperty("storePassword").toCharArray()) }
        val alias = properties.getProperty("keyAlias")
        check(keyStore.getKey(alias, properties.getProperty("keyPassword").toCharArray()) is PrivateKey)
        (keyStore.getCertificate(alias) as X509Certificate).also { it.checkValidity() }
    } catch (_: Exception) {
        throw GradleException("Cannot validate $label signing key. Check the local keystore, alias, passwords and certificate validity.")
    }
    check(label != "release" || !certificate.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true)) {
        "Release builds must not use the Android debug certificate."
    }
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    group = "verification"
    description = "Validate the external release key without exposing credentials."
    doLast { verifySigning("release", "key.properties", releaseSigningProperties) }
}
val verifyDebugSigning = tasks.register("verifyDebugSigning") {
    group = "verification"
    description = "Validate the existing external debug key; never regenerate it."
    doLast { verifySigning("debug", "debug.properties", debugSigningProperties) }
}

tasks.configureEach {
    when (name) {
        "preReleaseBuild", "validateSigningRelease" -> dependsOn(verifyReleaseSigning)
        "preDebugBuild", "validateSigningDebug", "preProfileBuild", "validateSigningProfile",
        "preDebugAndroidTestBuild", "validateSigningDebugAndroidTest" -> dependsOn(verifyDebugSigning)
    }
}

android {
    namespace = "com.islander.islander_flutter"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.islander.islander_flutter"
        manifestPlaceholders["appLabel"] = "岛民岛"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            storeFile = signingStore(debugSigningProperties)
            storeType = debugSigningProperties.getProperty("storeType", "PKCS12")
            storePassword = debugSigningProperties.getProperty("storePassword")
            keyAlias = debugSigningProperties.getProperty("keyAlias")
            keyPassword = debugSigningProperties.getProperty("keyPassword")
        }
        create("release") {
            storeFile = signingStore(releaseSigningProperties)
            storeType = releaseSigningProperties.getProperty("storeType", "PKCS12")
            storePassword = releaseSigningProperties.getProperty("storePassword")
            keyAlias = releaseSigningProperties.getProperty("keyAlias")
            keyPassword = releaseSigningProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "岛民岛调试版"
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("profile") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
