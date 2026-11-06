# Shared Claude memory

Project memory for Claude Code, versioned here so the team shares it. `MEMORY.md` is the index.

One-time local setup (cmd.exe): point Claude's per-project memory dir at this folder.
Replace the slug with your checkout path, e.g. `C--Users-you-Desktop-SpaceGame`.

```cmd
move "%USERPROFILE%\.claude\projects\<slug>\memory" "%USERPROFILE%\.claude\projects\<slug>\memory.bak"
mklink /J "%USERPROFILE%\.claude\projects\<slug>\memory" "<repo root>\memory"
```

Keep personal (`user`-type) memories out of this folder.
