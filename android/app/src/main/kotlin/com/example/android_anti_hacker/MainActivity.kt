package com.example.android_anti_hacker

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "anti_hacker/apps"

    private val sensitivePermissions = setOf(
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.READ_CONTACTS",
        "android.permission.WRITE_CONTACTS",
        "android.permission.READ_SMS",
        "android.permission.SEND_SMS",
        "android.permission.RECEIVE_SMS",
        "android.permission.READ_CALL_LOG",
        "android.permission.WRITE_CALL_LOG",
        "android.permission.READ_PHONE_STATE",
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.MANAGE_EXTERNAL_STORAGE",
        "android.permission.REQUEST_INSTALL_PACKAGES",
        "android.permission.SYSTEM_ALERT_WINDOW"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        try {
                            result.success(readInstalledApps())
                        } catch (e: Exception) {
                            result.error("SCAN_FAILED", e.localizedMessage ?: "Scan failed", null)
                        }
                    }
                    "uninstallApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("BAD_ARGUMENT", "Package name is missing", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName"))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("UNINSTALL_FAILED", e.localizedMessage ?: "Cannot open uninstall screen", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun installedPackages(): List<PackageInfo> {
        return if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getInstalledPackages(PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
        } else {
            packageManager.getInstalledPackages(PackageManager.GET_PERMISSIONS)
        }
    }

    private fun readInstalledApps(): List<Map<String, Any>> {
        return installedPackages().mapNotNull { info ->
            val packageName = info.packageName ?: return@mapNotNull null
            val appInfo = info.applicationInfo ?: return@mapNotNull null
            val label = packageManager.getApplicationLabel(appInfo)?.toString() ?: packageName
            val isSystem = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
            val permissions = info.requestedPermissions?.toList() ?: emptyList()
            val risky = permissions.filter { it in sensitivePermissions }

            // This is a permission-based triage only; it does not claim malware detection.
            val hasSeveralSensitive = risky.size >= 5
            val hasHighImpactCombo =
                "android.permission.REQUEST_INSTALL_PACKAGES" in risky &&
                ("android.permission.SYSTEM_ALERT_WINDOW" in risky ||
                 "android.permission.RECORD_AUDIO" in risky)
            val risk = when {
                hasHighImpactCombo -> "high"
                hasSeveralSensitive -> "review"
                risky.size >= 2 -> "review"
                else -> "safe"
            }
            val explanation = when (risk) {
                "high" -> "يطلب التطبيق مجموعة صلاحيات حساسة قد تستحق التحقق، وهذا لا يثبت أنه ضار."
                "review" -> "يطلب التطبيق صلاحيات حساسة. تحقق من سبب حاجته إليها ومن مصدر تثبيته."
                else -> "لم يظهر عدد مرتفع من الصلاحيات الحساسة ضمن الفحص المحدود."
            }

            mapOf(
                "name" to label,
                "packageName" to packageName,
                "isSystem" to isSystem,
                "permissions" to permissions,
                "riskyPermissions" to risky,
                "risk" to risk,
                "explanation" to explanation
            )
        }.sortedBy { (it["name"] as String).lowercase() }
    }
}
