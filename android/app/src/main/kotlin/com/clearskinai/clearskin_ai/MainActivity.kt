package com.clearskinai.clearskin_ai

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

// FlutterFragmentActivity is required by local_auth (biometric app lock).
class MainActivity : FlutterFragmentActivity() {
    private var integrityProvider: StandardIntegrityTokenProvider? = null
    private var preparedFor: Long = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.clearskinai/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // App-scoped ID (unique per signing key + device + user).
                    // Used only to stop free-quota abuse; never for ads.
                    "deviceId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
                    )
                    "appInfo" -> result.success(appInfo())
                    // With app lock on: blank in the recent-apps switcher and
                    // no screenshots, so face photos can't be seen there.
                    "setSecure" -> {
                        if (call.argument<Boolean>("secure") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "integrityToken" -> {
                        val project = (call.argument<Number>("projectNumber"))?.toLong()
                        val hash = call.argument<String>("requestHash")
                        if (project == null || project <= 0 || hash == null) {
                            result.error("bad_args", "projectNumber and requestHash required", null)
                        } else {
                            integrityToken(project, hash, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun appInfo(): Map<String, Any?> {
        val pm = packageManager
        val signers = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                info.signingInfo?.apkContentsSigners?.toList().orEmpty()
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures?.toList().orEmpty()
            }
        } catch (e: Exception) {
            emptyList()
        }
        val digests = signers.map { sig ->
            MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
                .joinToString(":") { "%02X".format(it) }
        }
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(packageName)
            }
        } catch (e: Exception) {
            null
        }
        return mapOf(
            "signingSha256" to digests,
            "installer" to installer,
            "debuggable" to ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
        )
    }

    /** Play Integrity standard request. The provider is prepared once and
     *  reused; Google recommends this for low-latency tokens. */
    private fun integrityToken(project: Long, hash: String, result: MethodChannel.Result) {
        val request = { provider: StandardIntegrityTokenProvider ->
            provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                .addOnSuccessListener { result.success(it.token()) }
                .addOnFailureListener {
                    // A stale provider is the usual cause; prepare afresh next time.
                    integrityProvider = null
                    result.error("integrity", it.message, null)
                }
        }
        val cached = integrityProvider
        if (cached != null && preparedFor == project) {
            request(cached)
            return
        }
        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build(),
            )
            .addOnSuccessListener { provider ->
                integrityProvider = provider
                preparedFor = project
                request(provider)
            }
            .addOnFailureListener { result.error("integrity", it.message, null) }
    }
}
