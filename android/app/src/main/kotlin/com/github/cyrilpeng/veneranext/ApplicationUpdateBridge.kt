package com.github.cyrilpeng.veneranext

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.zip.ZipFile

/** Owns the system handoff independently from the Flutter engine and its pages. */
internal class ApplicationUpdateBridge(private val activity: MainActivity) : ApplicationUpdateSessions.Listener {
    companion object {
        private val writer = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
    }

    private val preferences = activity.getSharedPreferences(ApplicationUpdateSessions.PREFERENCES, 0)
    private val packageInstaller get() = activity.packageManager.packageInstaller
    private var channel: MethodChannel? = null
    private var installReply: MethodChannel.Result? = null
    private var replyAttempt: String? = null
    private var permissionReply: MethodChannel.Result? = null

    private val permission = activity.activityResultRegistry.register(
        "leaf.update.permission", activity, ActivityResultContracts.StartActivityForResult()
    ) {
        permissionReply?.success(canInstall())
        permissionReply = null
    }

    fun attach(messenger: BinaryMessenger) {
        detach()
        ApplicationUpdateSessions.listener = this
        try { reconcileSessions() } catch (_: Exception) {}
        channel = MethodChannel(messenger, "leaf/application_update").also { channel ->
            channel.setMethodCallHandler { call, reply ->
                try {
                    when (call.method) {
                        "current" -> {
                            val current = currentPackage()
                            val installationPending = installationPending()
                            // Lets a rebuilt engine reopen or cancel a confirmation it never saw.
                            val attempt = if (installationPending) preferences.getString("attemptId", null) else null
                            val confirm = ApplicationUpdateSessions.confirmation
                            reply.success(mapOf("packageName" to current.packageName,
                                "versionCode" to code(current), "versionName" to current.versionName,
                                "debug" to isDebug(), "installationPending" to installationPending,
                                "attemptId" to attempt,
                                "awaitingConfirmation" to (attempt != null && confirm?.attempt == attempt &&
                                    ApplicationUpdateSessions.writingAttempt == null)))
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
                        "reopenConfirmation" -> {
                            reopenConfirmation(call.argument<String>("attemptId"))
                            reply.success(null)
                        }
                        "cancelInstallation" -> {
                            cancelInstallation(call.argument<String>("attemptId"))
                            reply.success(null)
                        }
                        "installationStatus" -> {
                            val id = call.argument<String>("attemptId") ?: throw IllegalArgumentException("Missing attempt ID")
                            reply.success(receipt(id))
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
        if (ApplicationUpdateSessions.listener === this) ApplicationUpdateSessions.listener = null
        // The session outlives this engine; report its current state instead of a guess.
        replyAttempt?.let { id ->
            installReply?.success(try { receipt(id) } catch (_: Exception) { receipt(id, "unknown") })
        }
        installReply = null
        replyAttempt = null
        permissionReply?.success(false)
        permissionReply = null
    }

    /** Called from onResume, before the lifecycle reports RESUMED. */
    fun resume() = handleConfirmation(true)

    override fun onConfirmation() =
        handleConfirmation(activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))

    private fun handleConfirmation(resumed: Boolean) {
        val confirm = ApplicationUpdateSessions.confirmation
        val waiting = confirm != null && confirm.attempt == preferences.getString("attemptId", null)
        when (ApplicationUpdatePolicy.confirmationAction(waiting, confirm?.launched == true, resumed)) {
            "launch" -> launchConfirmation()
            // Never relaunch automatically; the user chooses to reopen or cancel.
            "await" -> channel?.invokeMethod("awaitingConfirmation", mapOf("attemptId" to confirm!!.attempt))
        }
    }

    override fun onFinished(attemptId: String, status: String, message: String?) {
        if (attemptId != replyAttempt) return
        installReply?.success(receipt(attemptId, status, message))
        installReply = null
        replyAttempt = null
    }

    private fun launchConfirmation() {
        val confirm = ApplicationUpdateSessions.confirmation ?: return
        try {
            activity.startActivity(confirm.intent)
            confirm.launched = true
        } catch (error: Exception) {
            ApplicationUpdateSessions.abandon(activity, confirm.session)
            ApplicationUpdateSessions.finish(preferences, confirm.attempt, "failed", error.message)
        }
    }

    private fun requireOpenAttempt(id: String?): String {
        require(!id.isNullOrBlank() && preferences.getString("attemptId", null) == id) { "Unknown installation attempt" }
        check(ApplicationUpdateSessions.writingAttempt == null) { "Installation session is being written" }
        check(status(id) == "pending") { "Installation is not awaiting confirmation" }
        return id
    }

    private fun reopenConfirmation(attemptId: String?) {
        val id = requireOpenAttempt(attemptId)
        val confirm = ApplicationUpdateSessions.confirmation
        if (confirm != null && confirm.attempt == id) {
            try {
                activity.startActivity(confirm.intent)
                confirm.launched = true
                return
            } catch (error: Exception) {
                Log.w("ApplicationUpdate", "Confirmation intent unavailable", error)
            }
        }
        // Replace the unusable session from the verified local APK; an abandon failure
        // propagates and leaves the session pending.
        val previous = preferences.getInt("sessionId", -1)
        if (previous >= 0 && packageInstaller.getSessionInfo(previous) != null) {
            packageInstaller.abandonSession(previous)
        }
        ApplicationUpdateSessions.clearConfirmation(id)
        try {
            startSession(id)
        } catch (error: Exception) {
            // The old session is gone; end the attempt so the local APK can be retried.
            ApplicationUpdateSessions.finish(preferences, id, "failed", error.message)
        }
    }

    private fun cancelInstallation(attemptId: String?) {
        val id = requireOpenAttempt(attemptId)
        val session = preferences.getInt("sessionId", -1)
        if (session >= 0 && packageInstaller.getSessionInfo(session) != null) {
            packageInstaller.abandonSession(session)
        }
        ApplicationUpdateSessions.finish(preferences, id, "cancelled", null)
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

    private fun receipt(id: String, status: String, message: String? = null) =
        mapOf("attemptId" to id, "status" to status, "message" to message)

    private fun receipt(id: String): Map<String, String?> {
        val status = status(id)
        return receipt(id, status, if (status == "failed") preferences.getString("message", null) else null)
    }

    private fun targetInstalled(): Boolean {
        val current = currentPackage()
        val expected = preferences.getStringSet("signatures", null) ?: return false
        return preferences.getString("packageName", null) == current.packageName &&
            expected == signatures(current) && code(current) >= preferences.getLong("versionCode", Long.MAX_VALUE)
    }

    private fun committed(info: PackageInstaller.SessionInfo) = if (Build.VERSION.SDK_INT >= 29) {
        info.isCommitted
    } else {
        // Recorded before commit(), so an interrupted commit is conservatively treated as pending.
        info.sessionId == preferences.getInt("sessionId", -1) && preferences.getBoolean("committed", false)
    }

    private fun installedSafely() = try { targetInstalled() } catch (_: Exception) { false }

    private fun reconcileSessions() {
        val writing = ApplicationUpdateSessions.writingAttempt != null
        val recordedSession = preferences.getInt("sessionId", -1)
        for (info in packageInstaller.mySessions) {
            val committed = committed(info)
            val confirmationSession = ApplicationUpdateSessions.confirmation?.session
            val owned = ApplicationUpdatePolicy.ownsSession(info.sessionId,
                info.sessionId in ApplicationUpdateSessions.processSessions, confirmationSession)
            val decision = ApplicationUpdatePolicy.leftoverSession(committed, writing, owned,
                committed && installedSafely())
            if (ApplicationUpdatePolicy.dropsConfirmation(decision, info.sessionId, confirmationSession)) {
                ApplicationUpdateSessions.clearConfirmation(info.sessionId)
            }
            when (decision) {
                "abandon" -> ApplicationUpdateSessions.abandon(activity, info.sessionId)
                "installed", "orphaned" -> {
                    val abandoned = try {
                        packageInstaller.abandonSession(info.sessionId)
                        true
                    } catch (error: Exception) {
                        Log.w("ApplicationUpdate", "Cannot abandon orphaned session", error)
                        false
                    }
                    val result = if (decision == "installed") "installed" else ApplicationUpdatePolicy.orphanedResult(abandoned)
                    if (info.sessionId == recordedSession && result != "pending") {
                        preferences.edit().putString("status", result).remove("message").commit()
                    }
                }
            }
        }
    }

    // An installed target releases the update even if its stale session could not be abandoned.
    private fun installationPending() = ApplicationUpdateSessions.writingAttempt != null ||
        (packageInstaller.mySessions.any { committed(it) } && !installedSafely())

    private fun status(id: String): String {
        if (preferences.getString("attemptId", null) != id) return "unknown"
        val session = preferences.getInt("sessionId", -1)
        val info = if (session < 0) null else packageInstaller.getSessionInfo(session)
        return ApplicationUpdatePolicy.attemptStatus(targetInstalled(), preferences.getString("status", null),
            ApplicationUpdateSessions.writingAttempt == id, info?.let { committed(it) })
    }

    private fun install(version: String?, id: String?, reply: MethodChannel.Result) {
        require(!id.isNullOrBlank() && id.length <= 128) { "Invalid installation attempt ID" }
        require(!version.isNullOrBlank()) { "Missing update version" }
        check(!isDebug()) { "Debug builds cannot install release updates" }
        if (preferences.getString("attemptId", null) == id) { reply.success(receipt(id)); return }
        reconcileSessions()
        check(!installationPending()) { "A previous installation is still in progress" }
        check(installReply == null) { "Installer is already active" }
        check(canInstall()) { "Installation permission has not been granted" }
        val candidate = inspect(false)
        check(candidate.versionName == version) { "Update version does not match release" }
        // Commit before creating the session, outside cacheDir, so restart can correlate it.
        check(preferences.edit().clear().putString("attemptId", id)
            .putString("packageName", candidate.packageName).putLong("versionCode", code(candidate))
            .putStringSet("signatures", signatures(candidate)).commit()) { "Cannot persist installation handoff" }
        startSession(id)
        // Results arrive through posted callbacks, so a synchronous failure above never replies twice.
        installReply = reply
        replyAttempt = id
    }

    /** Writes a new session for the recorded attempt from the fixed, re-inspected candidate. */
    private fun startSession(id: String) {
        val candidate = inspect(false)
        check(preferences.getString("packageName", null) == candidate.packageName &&
            preferences.getLong("versionCode", -1) == code(candidate)) { "Update package changed" }
        check(code(candidate) > code(currentPackage())) { "Update version code must be newer" }
        val file = candidateFile(false)
        check(preferences.edit().remove("sessionId").remove("committed").remove("status")
            .remove("message").commit()) { "Cannot persist installation handoff" }
        ApplicationUpdateSessions.writingAttempt = id
        val context = activity.applicationContext
        writer.execute {
            val failure = try { writeSession(context, file, id); null } catch (error: Exception) { error }
            main.post {
                ApplicationUpdateSessions.writingAttempt = null
                if (failure != null) {
                    ApplicationUpdateSessions.finish(preferences, id, "failed",
                        failure.message ?: "Cannot write installation session")
                }
            }
        }
    }

    /** Streams the fixed candidate into a new session; runs off the main thread. */
    private fun writeSession(context: Context, file: File, id: String) {
        val installer = context.packageManager.packageInstaller
        val length = file.length()
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(length)
        }
        val session = installer.createSession(params)
        var committed = false
        try {
            check(preferences.edit().putInt("sessionId", session).commit()) { "Cannot persist installation session" }
            installer.openSession(session).use { opened ->
                FileInputStream(file).use { input ->
                    opened.openWrite("base.apk", 0, length).use { output ->
                        input.copyTo(output)
                        opened.fsync(output)
                    }
                }
                check(preferences.edit().putBoolean("committed", true).commit()) { "Cannot persist installation session" }
                // Explicit receiver; mutable so the installer can add status extras.
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val result = Intent(context, ApplicationUpdateReceiver::class.java)
                    .putExtra(ApplicationUpdateSessions.EXTRA_ATTEMPT, id)
                ApplicationUpdateSessions.processSessions.add(session)
                opened.commit(PendingIntent.getBroadcast(context, session, result, flags).intentSender)
                committed = true
            }
        } catch (error: Exception) {
            // After commit the system owns the session and reports through the receiver.
            if (committed) return
            ApplicationUpdateSessions.processSessions.remove(session)
            ApplicationUpdateSessions.abandon(context, session)
            throw error
        }
    }
}
