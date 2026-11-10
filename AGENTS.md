# Bottogram project instructions

## Complete every change with a commit and restart

After every completed change in this project:

1. Run the checks appropriate to the change and resolve failures caused by it.
2. Create a Git commit containing that change. Write the commit subject and body
   in English. Include only the current task's changes; coordinate with other
   chats before including their pending work, and never commit secrets or local
   application data.
3. Restart the running Bottogram preview so the user can see the result. For
   application changes, rebuild the affected app or package first and launch the
   updated build rather than a stale executable. A documentation-only change
   does not require rebuilding the application.
4. Verify that the restarted application remains running and report the actual
   application PID. If a development server is involved, verify and report its
   actual listening addresses and ports as well.

Perform the commit and restart automatically as part of the task; do not leave
terminal commands or a manual restart for the user. Preserve saved application
data and explain that restarting stops any running bots. If a required check,
commit or restart is blocked, report the concrete blocker instead of claiming
the change is complete.
