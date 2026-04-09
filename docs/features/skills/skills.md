# Skill Browser

The Skill Browser lets you view and explore the Claude Code skills (`.agents/skills/`) available in a repository.

Available in the **Skills** tab of the Mac app and via `ai-dev-tools-kit skills --help` in the CLI.

## What Are Skills?

Skills are markdown files that extend Claude Code's behavior — they define specialized instructions, workflows, or prompts that Claude can invoke for specific tasks. Each skill lives in `.agents/skills/<skill-name>/SKILL.md` (or `.claude/skills/` via symlink) within a repository.

## What the Browser Shows

For a selected repository, the Skill Browser lists all discovered skills and displays their content. This makes it easy to:

- See which skills are available without navigating the filesystem
- Read a skill's instructions before invoking it in Claude Code
- Understand what a skill does (trigger conditions, behavior, references)

Skills are loaded from the repository's skill directory and displayed as a navigable list with their full markdown content.
