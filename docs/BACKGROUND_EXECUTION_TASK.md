# Background execution and battery-exemption setup

Recorded: 2026-11-09 (Asia/Tehran).

Status: implemented service, shared engine, lifecycle coordinator, settings checks and guide. Verification and limitations are recorded in [Plugin runtime](PLUGIN_RUNTIME.md). Physical-device OEM behavior remains a separate device check.

## Goal and scope

Keep user-started bots working when Bottogram's UI is in the background or the screen is off. Add battery/background setup guidance that repeats until the actual system requirement is satisfied. This requirement supersedes the earlier foreground-only runtime proposal in [IDEAS.md](IDEAS.md) and [PLUGIN_IMPLEMENTATION_PLAN.md](PLUGIN_IMPLEMENTATION_PLAN.md).

Battery exemption is one prerequisite, not evidence that the bot runtime is alive. The task includes a supported Android background runtime as well as the prompt and warning. Real Inshopa API integration remains deferred; documenting background support does not enable setup-only plugins or start stopped bots.

## Required user experience

1. On every app opening, check whether Bottogram is actually exempt from Android battery optimization. If it is not, automatically show an explanatory in-app prompt/page once for that opening.
2. Explain why bots need background execution, how to exempt Bottogram from battery optimization, and any additional supported background setting needed on the device. Explain the battery-use impact in plain language.
3. 🟣 The user can follow the instructions and use an **Open battery settings** button to reach the supported system settings screen. Include an **Open app settings** button for Bottogram's own Android app-details page.
4. 🟣 The user can dismiss or skip the guide for the current opening and continue using the app. Skipping must not permanently suppress it: show it once again on the next opening until exemption is confirmed. Do not add a permanent “already explained” flag as a substitute for system state.
5. Recheck the system state when returning from settings. Opening settings, pressing a button, or dismissing a system dialog is not proof of exemption. If exemption is later revoked, resume the warning and next-opening prompt.
6. Keep a fixed warning at the top of the app while battery/background setup is incomplete. Keep it visible across main screens and scrolling, with clear status and a **Read instructions** action that reopens the same guide. Provide the app-settings shortcut there or in that guide. If exemption is granted but another background requirement is missing, explain that actual missing requirement instead of falsely reporting that battery exemption is absent.
7. Avoid duplicate prompts caused by rebuilds, navigation, rotation, or the return from the guide's own system-settings flow. Treat a normal reopening from the background as a new opening; returning from this settings flow should update status without creating an immediate prompt loop. The warning remains available after a skipped guide.

## State checks and supported settings navigation

- Use Android's actual exemption status, such as `PowerManager.isIgnoringBatteryOptimizations(packageName)`, behind a supported Flutter integration. Keep battery exemption, other background restrictions, and runtime health as distinct states. Unknown/unreadable state must not appear as “ready.” [PowerManager reference](https://developer.android.com/reference/android/os/PowerManager#isIgnoringBatteryOptimizations(java.lang.String))
- Use supported settings actions: `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` and `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` with the app's package URI. Check that an activity can handle the action, and show usable instructions if it cannot. Direct exemption requests, if chosen, require verifying their documented eligibility/permission requirements first. [Settings reference](https://developer.android.com/reference/android/provider/Settings#ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
- Opening an Android settings page remains a user action. Do not change system settings automatically or rely on undocumented manufacturer-specific activity names. Do not describe a permission grant or exemption as proof of an operating network connection.

## Background runtime work

- Design and implement the Android execution mechanism that can keep explicitly started bots running beyond Flutter's visible screen lifecycle. Preserve existing Start/Stop/Delete behavior, one Telegram update consumer per bot, plugin isolation, saved progress, and the inbox capture path. Minimized UI alone must no longer mean “stop the bot.”
- Review the applicable foreground-service type, permissions, user-visible service notification, start restrictions, timeouts, and service shutdown/recovery for the app's supported Android versions and target SDK before choosing the implementation. Preserve user control over stopping work. No database migration is approved by this task; any required migration still needs its separately scoped approval.
- Battery exemption alone cannot guarantee indefinite execution under every Android/OEM condition. Document and test the limits, including force-stop, process death, network loss, and device restart. Define recovery behavior explicitly instead of promising that the app can bypass those conditions. [Android Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- In particular, a permanent `dataSync` foreground service is not automatically an always-on solution: apps targeting Android 15+ have a six-hour background budget per 24 hours for that service type. Resolve the applicable service design and limits rather than claiming exemption removes them. [Foreground service timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout)

## Acceptance checks for implementation

- A fresh, non-exempt installation shows the guide once on opening. Dismiss, background/reopen, and cold restart each give the required next-opening reminder without duplicate dialogs within one opening.
- The pinned warning stays visible after dismissal and its guide/settings actions work from the main app screens. Verify small screens, keyboard visibility, large text, and RTL layout.
- Visiting settings without granting exemption leaves the requirement incomplete. Granting exemption refreshes the displayed state; reopening while exempt does not show the battery-exemption prompt. Revoking it restores the next-opening prompt and warning.
- A settings round trip does not immediately reopen the same prompt. Unsupported settings intents and failed state reads produce actionable, truthful UI rather than a crash or false success.
- Readiness/status text reflects the separate battery/background/runtime states; a stopped bot is not reported as running. Existing bot controls, plugin preferences, and inbox behavior continue to work.
- 🟣 On real Android devices, verify user-started bot operation while minimized, with screen off and under Doze; verify explicit Stop/Delete, service notification behavior, and documented process-death/force-stop/restart limits. Include the minimum supported Android version and current target behavior, and record device-specific limitations.
- Test the future Inshopa runner's background behavior only after its API/runtime work is implemented. Until then, retain its explicit setup-only state.

Completion requires both the setup UX and verified background execution. Showing the guide or obtaining battery exemption alone does not complete this task.
