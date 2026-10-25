package com.github.cyrilpeng.veneranext

import android.content.ClipData
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipFile

/** Owns the system handoff independently from the Flutter engine and its pages. */
internal class ApplicationUpdateBridge(private val activity: MainActivity) {
    companion object {
        private val processId = UUID.randomUUID().toString()
        private const val STATE_ATTEMPT = "leaf.update.attempt"
        private const val STATE_PROCESS = "leaf.update.process"
    }

    private val preferences = activity.getSharedPreferences("application_update_handoff", 0)
    private var channel: MethodChannel? = null
    private var installReply: MethodChannel.Result? = null
    private var permissionReply: MethodChannel.Result? = null
    private var launchedAttempt: String? = null
    private var sameProcess = true

    // Fixed keys and unconditional lifecycle registration let Android restore pending results.
    private val installer = activity.activityResultRegistry.register(
        "leaf.update.installer", activity, ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val id = launchedAttempt
        val storedId = preferences.getString("attemptId", null)
        if (id != null && id == storedId) {
            val status = try {
                ApplicationUpdatePolicy.resultStatus(targetInstalled(), sameProcess, result.resultCode)
            } catch (_: Exception) { "unknown" }
            // A persistence failure cannot release the on-disk ownership record.
            val durableStatus = if (preferences.edit().putString("status", status).commit()) status else "unknown"
            installReply?.success(receipt(id, durableStatus))
        } else {
            installReply?.success(receipt(id ?: "", "unknown"))
        }
        installReply = null
        launchedAttempt = null
    }
    private val permission = activity.activityResultRegistry.register(
        "leaf.update.permission", activity, ActivityResultContracts.StartActivityForResult()
    ) {
        permissionReply?.success(canInstall())
        permissionReply = null
    }

    fun restore(state: Bundle?) {
        launchedAttempt = state?.getString(STATE_ATTEMPT)
        sameProcess = state == null || state.getString(STATE_PROCESS) == processId
    }

    fun save(state: Bundle) {
        state.putString(STATE_ATTEMPT, launchedAttempt)
        state.putString(STATE_PROCESS, processId)
    }

    fun attach(messenger: BinaryMessenger) {
        detach()
        channel = MethodChannel(messenger, "leaf/application_update").also { channel ->
            channel.setMethodCallHandler { call, reply ->
                try {
                    when (call.method) {
                        "current" -> {
                            val current = currentPackage()
                            val previous = preferences.getString("attemptId", null)
                            val installationPending = previous != null &&
                                ApplicationUpdatePolicy.occupiesInstaller(status(previous))
                            reply.success(mapOf("packageName" to current.packageName,
                                "versionCode" to code(current), "versionName" to current.versionName,
                                "debug" to isDebug(), "installationPending" to installationPending))
                        }
                        "inspect" -> {
                            val candidate = inspect(call.argument<Boolean>("partial") == true)
                            reply.success(mapOf("versionCode" to code(candidate),
                                "versionName" to candidate.versionName,
                                "installedVersionCode" to code(currentPackage())))
                        }
                        "canInstall" -> reply.success(canInstall())
                        "requestPermission" -> requestPermission(reply)
                        "install" -> install(call.argument<String>("version"), call.argument<String>("attemptId"), reply)
                        "installationStatus" -> {
                            val id = call.argument<String>("attemptId") ?: throw IllegalArgumentException("Missing attempt ID")
                            reply.success(receipt(id, status(id)))
                        }
                        else -> reply.notImplemented()
                    }
                } catch (error: Exception) {
                    reply.error("application_update", error.message ?: "Update operation failed", null)
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        installReply?.success(receipt(launchedAttempt ?: "", "unknown"))
        installReply = null
        permissionReply?.success(false)
        permissionReply = null
    }

    private fun isDebug() = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private fun canInstall() = !isDebug() &&
        (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls())

    private fun requestPermission(reply: MethodChannel.Result) {
        check(!isDebug()) { "Debug builds cannot install release updates" }
        check(permissionReply == null) { "Installation permission request is already active" }
        if (canInstall()) { reply.success(true); return }
        permissionReply = reply
        try {
            permission.launch(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
        } catch (error: Exception) {
            permissionReply = null
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun signatureFlags() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    @Suppress("DEPRECATION")
    private fun currentPackage(): PackageInfo = activity.packageManager.getPackageInfo(activity.packageName, signatureFlags())
    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val values = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        check(!values.isNullOrEmpty()) { "Package signing certificates unavailable" }
        return values.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }

    private fun candidateFile(partial: Boolean) = ApplicationUpdatePolicy.candidateFile(activity.cacheDir, partial)

    private fun inspect(partial: Boolean): PackageInfo {
        check(!isDebug()) { "Debug builds cannot install release updates" }
        val file = candidateFile(partial)
        val candidate = activity.packageManager.getPackageArchiveInfo(file.path, signatureFlags())
            ?: throw IllegalArgumentException("Cannot parse update APK")
        val current = currentPackage()
        check(candidate.packageName == current.packageName) { "Update package name does not match" }
        check(signatures(candidate) == signatures(current)) { "Update signing certificates do not match" }
        check(candidate.applicationInfo?.flags?.and(ApplicationInfo.FLAG_DEBUGGABLE) == 0) { "Debug APK cannot be installed as an update" }
        ZipFile(file).use { zip ->
            ApplicationUpdatePolicy.validateLibraries(zip.entries().asSequence().map { it.name }.toList())
        }
        return candidate
    }

    private fun receipt(id: String, status: String) = mapOf("attemptId" to id, "status" to status)

    private fun targetInstalled(): Boolean {
        val current = currentPackage()
        val expected = preferences.getStringSet("signatures", null) ?: return false
        return preferences.getString("packageName", null) == current.packageName &&
            expected == signatures(current) && code(current) >= preferences.getLong("versionCode", Long.MAX_VALUE)
    }

    private fun status(id: String): String {
        if (preferences.getString("attemptId", null) != id) return "unknown"
        if (targetInstalled()) return "installed"
        val recorded = preferences.getString("status", "unknown")
        return if (recorded == "cancelled" || recorded == "failed") recorded else "unknown"
    }

    private fun install(version: String?, id: String?, reply: MethodChannel.Result) {
        require(!id.isNullOrBlank() && id.length <= 128) { "Invalid installation attempt ID" }
        require(!version.isNullOrBlank()) { "Missing update version" }
        check(!isDebug()) { "Debug builds cannot install release updates" }
        val previous = preferences.getString("attemptId", null)
        if (previous == id) { reply.success(receipt(id, status(id))); return }
        check(previous == null || !ApplicationUpdatePolicy.occupiesInstaller(status(previous))) {
            "A previous installation has an unknown result"
        }
        check(installReply == null && launchedAttempt == null) { "Installer is already active" }
        check(canInstall()) { "Installation permission has not been granted" }
        val candidate = inspect(false)
        check(candidate.versionName == version) { "Update version does not match release" }
        check(code(candidate) > code(currentPackage())) { "Update version code must be newer" }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", candidateFile(false))
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("Leaf update", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }
        // Commit before handoff, outside cacheDir, so missing Dart metadata cannot erase ownership.
        check(preferences.edit().clear().putString("attemptId", id).putString("status", "unknown")
            .putString("packageName", candidate.packageName).putLong("versionCode", code(candidate))
            .putStringSet("signatures", signatures(candidate)).commit()) { "Cannot persist installation handoff" }
        launchedAttempt = id
        sameProcess = true
        installReply = reply
        try {
            installer.launch(intent)
        } catch (_: Exception) {
            // Launch exceptions need not prove that an external reader never started.
            installReply = null
            launchedAttempt = null
            reply.success(receipt(id, "unknown"))
        }
    }
}
