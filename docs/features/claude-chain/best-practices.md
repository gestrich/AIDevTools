# Best Practices

A guide to evaluating whether ClaudeChain is right for your project and how to set yourself up for success.

## When to Use ClaudeChain

### Ideal Projects

**Repeatable tasks.** The same type of work over and over—updating documentation, migrating APIs, refactoring patterns.

**Well-specified tasks.** Can you describe it with a prompt the AI can get right most of the time? Complex is fine, as long as you can specify the rules and background needed. The key is one prompt that applies across multiple steps.

### Less Ideal Projects

Tasks where each step needs significantly different instructions don't fit the ClaudeChain model well. You won't iterate on the same prompt, so each will be less tested and more error-prone.

That said, some teams still find value in ClaudeChain as an orchestration tool—PRs get staged with an initial attempt, and the chain structure keeps work moving and tracked. You may decide the benefit of having PRs automatically staged is worth it, even if many need significant rework.

### The Long-Term Payoff

For the right problems, ClaudeChain scales your efforts indefinitely. The chain keeps running, keeps creating PRs, keeps reminding you to make progress—long after you would have forgotten about a refactoring project you planned months ago. But you have to select the right kind of problem and commit to the iteration process.

## Prompting

Prompting is central to ClaudeChain success. Expect to invest significant time here.

### Iterate on Your Prompts

A common mistake: trying ClaudeChain once, getting poor results, and walking away. This is expected. Your initial prompts will not be good enough.

You're going to need to iterate. That might take days of refinement. Evaluate whether that investment is worth the time you'll save over the long run.

### Experiment Locally First

Don't wait for CI to test your prompts. Run Claude Code locally, test your prompt against the task, and iterate until you're getting consistent results. Local iteration is faster and cheaper.

Once you have a prompt that works reliably, deploy it as a ClaudeChain project.

### Early PRs Will Need Refinement

For your first several PRs, expect to watch closely and make changes. This isn't wasted time—you're discovering edge cases and gaps in your prompt. When you find issues, update the prompt to handle them.

### Update Prompts in the Same PR

When a PR reveals a prompt issue, consider fixing the prompt in that same PR rather than staging a separate change. This keeps the chain moving quickly and associates the prompt fix with the context where it was discovered.

### Complex Problems: Different Prompts per Step

If your steps are significantly different from each other, you can provide different prompting for each step. This works, but recognize the tradeoffs—each prompt gets less iteration and testing, so expect more failures. If steps are truly different problems, consider separate chains where you can iterate on a consistent prompt.

### Scaling: Assign Chains to Multiple Individuals

For large projects, divide the work—split into logical sections, create separate chains for each, and assign different developers. This lets multiple people work in parallel, spreading the review burden.

## CI and DevOps Preparation

ClaudeChain runs in GitHub Actions, which means CI needs access to everything Claude needs.

### Give AI Access to Your Tools

If you have scripts, tests, validators, or other tools you run during development, be prepared to make them available in CI. Claude needs to run the same tooling you would run locally.

This includes:
- Build tools and compilers
- Test frameworks
- Linters and formatters
- Custom validation scripts
- Any tools required by your workflow

## Reviews and Team Expectations

ClaudeChain creates PRs for human review. Human oversight remains essential.

### The Assignee Owns the Code

The assignees are responsible for every PR in their chain. If the assignees don't understand the code, the PR should not be merged. Claude is helping stage the PR, but the humans assigned are responsible for validating what was done.

### Set Clear Expectations

When you assign a chain to someone, be explicit:

- How often should they review PRs? Daily? Weekly?
- What's the expected turnaround time?
- Who do they contact if they're blocked?

Without clear expectations, the chain becomes another nagging notification rather than a useful tool.

ClaudeChain has a configurable stale threshold—PRs open longer than this show as overdue in Slack notifications and statistics reports. Use this to give developers visibility into how on top of their PRs they are.

### Work Out Review Requirements

ClaudeChain generates many small PRs. This may require adjusting your normal review process. For example, documentation PRs probably don't need the same QA review as code changes.

If your organization has quality gates, get QA in the loop early. Discuss which PRs need review, how to handle the volume, and whether review happens per-PR or at the end.

### Branching Strategies

**Direct to main.** Each PR merges directly to your main branch. Quality review happens on each PR.

**Feature branch.** PRs merge to an intermediate feature branch. Quality review happens once at the end.

Either works—choose based on your team's workflow.
