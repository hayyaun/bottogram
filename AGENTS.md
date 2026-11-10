# Bottogram project instructions

## Complete every change with a scoped commit and appropriate preview refresh

After every completed change in this project:

1. Run the checks appropriate to the change and resolve failures caused by it.
2. Create a Git commit containing that change. Write the commit subject and body
   in English. Include only the current task's changes; coordinate with other
   chats before including their pending work, and never commit secrets or local
   application data.
3. For Dart application changes, prefer Flutter hot restart (`R`) through the
   existing attached debug session. Keep the Flutter session available for future
   changes. Do not stop and relaunch the whole application when hot restart is
   sufficient. Hot reload (`r`) is also suitable when preserving state is desired
   and the edited code will be re-executed correctly.
   Start the Linux preview with Flutter's supported
   `--pid-file build/verification/flutter-run.pid` option. If its original terminal
   is unavailable, verify that the recorded PID belongs to this project's Flutter
   session, then send SIGUSR2 to that tool PID for the equivalent of `R` (SIGUSR1
   is `r`). Do not send these signals to the application PID.
4. Rebuild and fully restart only when required, such as native/platform code,
   native dependencies, build configuration changes, or a preview that cannot
   apply the change through Flutter's supported hot restart. If the preview is a
   standalone build, establish an attached Flutter debug session when practical
   so subsequent Dart changes can use `R`. Explain why a full restart is needed.
5. Documentation-only and repository-tooling changes (including AGENTS.md,
   Graphify outputs and ignore rules) do not need an application restart unless
   they also affect runtime behavior. Do not restart solely to satisfy this file.
6. After a refresh, verify that the application remains running and that the
   change took effect. Report the actual application PID and any actual listening
   addresses and ports; do not report a launcher or Flutter-tool PID as the app.

Perform the commit and any necessary refresh automatically; do not leave terminal
commands or a manual restart for the user. Preserve saved application data.
Explain that hot restart resets in-memory state and stops running bots; a full
restart also stops running bots. If a required check, commit or refresh is
blocked, report the concrete blocker instead of claiming the change is complete.
