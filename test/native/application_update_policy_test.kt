package com.github.cyrilpeng.veneranext

import java.io.File
import java.nio.file.Files

private fun rejects(action: () -> Unit) {
    var rejected = false
    try { action() } catch (_: RuntimeException) { rejected = true }
    check(rejected) { "Unsafe APK was accepted" }
}

fun main() {
    val root = Files.createTempDirectory("update-policy-").toFile().canonicalFile
    try {
        val external = File(root, "sentinel.apk").apply { writeText("kept") }
        val directory = File(root, "updates").apply { mkdir() }
        val candidate = File(directory, "update.apk").apply { writeText("apk") }
        check(ApplicationUpdatePolicy.candidateFile(root, false) == candidate)
        rejects { ApplicationUpdatePolicy.candidateFile(root, true) }
        candidate.delete()
        Files.createSymbolicLink(candidate.toPath(), external.toPath())
        rejects { ApplicationUpdatePolicy.candidateFile(root, false) }
        candidate.delete()
        directory.delete()
        Files.createSymbolicLink(directory.toPath(), root.toPath())
        rejects { ApplicationUpdatePolicy.candidateFile(root, false) }
        directory.delete()
        check(external.readText() == "kept")
        println("PASS: fixed candidate path, missing partial, file symlink and directory symlink rejected")
    } finally { root.deleteRecursively() }
    val valid = listOf("AndroidManifest.xml", "lib/arm64-v8a/libflutter.so", "lib/arm64-v8a/libapp.so")
    ApplicationUpdatePolicy.validateLibraries(valid)
    rejects { ApplicationUpdatePolicy.validateLibraries(valid + "lib/x86/libapp.so") }
    rejects { ApplicationUpdatePolicy.validateLibraries(valid - "lib/arm64-v8a/libapp.so") }
    rejects { ApplicationUpdatePolicy.validateLibraries(valid + "lib/arm64-v8a/../libother.so") }
    rejects { ApplicationUpdatePolicy.validateLibraries(valid + "lib/arm64-v8a/libapp.so") }
    println("PASS: ARM64 release libraries, mixed ABI, missing app, traversal, duplicate library")
    // PackageInstaller.STATUS_* values: PENDING_USER_ACTION -1, SUCCESS 0, FAILURE 1,
    // BLOCKED 2, ABORTED 3, INVALID 4, CONFLICT 5, STORAGE 6, INCOMPATIBLE 7, TIMEOUT 8.
    check(ApplicationUpdatePolicy.sessionResult(-1) == null)
    check(ApplicationUpdatePolicy.sessionResult(0) == "installed")
    check(ApplicationUpdatePolicy.sessionResult(3) == "cancelled")
    for (status in listOf(1, 2, 4, 5, 6, 7, 8, 42)) {
        check(ApplicationUpdatePolicy.sessionResult(status) == "failed")
    }
    println("PASS: session status codes map to installed, cancelled, failed or awaiting confirmation")
    fun leftover(committed: Boolean, writing: Boolean = false, owned: Boolean = false, installed: Boolean = false) =
        ApplicationUpdatePolicy.leftoverSession(committed, writing, owned, installed)
    check(leftover(committed = false) == "abandon")
    check(leftover(committed = false, owned = true) == "abandon")
    check(leftover(committed = false, writing = true) == "keep")
    check(leftover(committed = true, writing = true) == "keep")
    println("PASS: leftover uncommitted sessions are abandoned except while this process writes one")
    check(leftover(committed = true, owned = true) == "pending")
    check(leftover(committed = true, owned = true, installed = true) == "pending")
    // Committed by a previous process: its confirmation intent is gone.
    check(leftover(committed = true, installed = true) == "installed")
    check(leftover(committed = true) == "orphaned")
    check(ApplicationUpdatePolicy.orphanedResult(abandoned = true) == "cancelled")
    check(ApplicationUpdatePolicy.orphanedResult(abandoned = false) == "pending")
    println("PASS: orphaned committed sessions resolve to installed, cancelled, or stay pending if abandon fails")
    // The receiver restarted the process after the committing one was killed and stored the
    // confirmation; the new process has no committed-session record of its own.
    check(ApplicationUpdatePolicy.ownsSession(7, committedByProcess = false, confirmationSession = 7))
    check(ApplicationUpdatePolicy.ownsSession(7, committedByProcess = true, confirmationSession = null))
    check(!ApplicationUpdatePolicy.ownsSession(7, committedByProcess = false, confirmationSession = 8))
    check(!ApplicationUpdatePolicy.ownsSession(7, committedByProcess = false, confirmationSession = null))
    val received = ApplicationUpdatePolicy.ownsSession(7, false, 7)
    check(leftover(committed = true, owned = received) == "pending")
    check(!ApplicationUpdatePolicy.dropsConfirmation("pending", 7, 7))
    check(!ApplicationUpdatePolicy.dropsConfirmation("keep", 7, 7))
    // Any session ended during reconciliation clears its stored confirmation.
    for (decision in listOf("orphaned", "installed", "abandon")) {
        check(ApplicationUpdatePolicy.dropsConfirmation(decision, 7, 7))
        check(!ApplicationUpdatePolicy.dropsConfirmation(decision, 7, 8))
        check(!ApplicationUpdatePolicy.dropsConfirmation(decision, 7, null))
    }
    println("PASS: a received confirmation keeps its session pending; ended sessions drop their confirmation")
    for (recorded in listOf(null, "cancelled", "failed")) {
        check(ApplicationUpdatePolicy.attemptStatus(true, recorded, false, null) == "installed")
    }
    check(ApplicationUpdatePolicy.attemptStatus(false, "cancelled", false, true) == "cancelled")
    check(ApplicationUpdatePolicy.attemptStatus(false, "failed", false, null) == "failed")
    check(ApplicationUpdatePolicy.attemptStatus(false, null, true, null) == "pending")
    check(ApplicationUpdatePolicy.attemptStatus(false, null, false, true) == "pending")
    // Lost callback: once the session is gone or left uncommitted, the attempt has ended.
    check(ApplicationUpdatePolicy.attemptStatus(false, null, false, null) == "failed")
    check(ApplicationUpdatePolicy.attemptStatus(false, null, false, false) == "failed")
    check(ApplicationUpdatePolicy.attemptStatus(false, "corrupt", false, null) == "failed")
    println("PASS: installed identity first, then callbacks, then live session state")
    fun action(waiting: Boolean, launched: Boolean, resumed: Boolean) =
        ApplicationUpdatePolicy.confirmationAction(waiting, launched, resumed)
    check(action(waiting = true, launched = false, resumed = true) == "launch")
    check(action(waiting = true, launched = false, resumed = false) == "none")
    check(action(waiting = false, launched = false, resumed = true) == "none")
    // Returning after leaving the system UI asks the user instead of relaunching it.
    check(action(waiting = true, launched = true, resumed = true) == "await")
    check(action(waiting = true, launched = true, resumed = false) == "none")
    println("PASS: confirmation launches once when resumed; a later resume awaits the user")
    check(ApplicationUpdatePolicy.occupiesInstaller("pending"))
    for (status in listOf("installed", "cancelled", "failed", "unknown")) {
        check(!ApplicationUpdatePolicy.occupiesInstaller(status))
    }
    println("PASS: only an active write or committed session keeps the attempt occupied")
}
