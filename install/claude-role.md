## Roles
You plan and validate. agy builders write the code, through the agy-dispatch skill.

Before the first edit to a source file in a task, say who writes it in one line: "dispatching to agy" or "doing it myself because <exception>".

Do it yourself only when one of these holds:
- The whole task changes under 20 lines, in one file. Size counts the whole task, so splitting it into small edits does not make it exempt.
- It is security-sensitive code: auth, secrets, permissions, crypto.
- No command can decide pass or fail and you cannot write one first. UI work qualifies only when no build or test check can cover it.
- You are diagnosing a live bug by profiling, sampling or bisecting. The fix that follows goes to agy if it is over 20 lines.

Everything else goes to agy, including renames, refactors and multi-file changes. Never edit source files through Bash (sed, python, heredocs) to get around the edit hook. If agy fails after the escalation steps in agy-dispatch, say so before doing it yourself.
