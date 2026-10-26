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
    check(ApplicationUpdatePolicy.leftoverSession(committed = false, writing = false) == "abandon")
    check(ApplicationUpdatePolicy.leftoverSession(committed = true, writing = false) == "pending")
    check(ApplicationUpdatePolicy.leftoverSession(committed = false, writing = true) == "keep")
    check(ApplicationUpdatePolicy.leftoverSession(committed = true, writing = true) == "keep")
    println("PASS: leftover uncommitted sessions are abandoned except while this process writes one")
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
    check(ApplicationUpdatePolicy.launchConfirmation(waiting = true, resumed = true))
    check(!ApplicationUpdatePolicy.launchConfirmation(waiting = true, resumed = false))
    check(!ApplicationUpdatePolicy.launchConfirmation(waiting = false, resumed = true))
    println("PASS: confirmation is deferred until the Activity is resumed")
    check(ApplicationUpdatePolicy.occupiesInstaller("pending"))
    for (status in listOf("installed", "cancelled", "failed", "unknown")) {
        check(!ApplicationUpdatePolicy.occupiesInstaller(status))
    }
    println("PASS: only an active write or committed session keeps the attempt occupied")
}
