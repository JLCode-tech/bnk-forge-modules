# /status - Quick Project Status Check

## When to Use

Use this skill to get a quick overview of the repository state:
- At the start of a session to understand current state
- Before making changes
- To check what's in progress
- To verify repository health

## What This Skill Does

Provides a comprehensive status report including:
- Git repository status
- Current branch and recent commits
- Active work from `.agent/CURRENT_WORK.md`
- Module structure overview
- Any uncommitted changes

## Step-by-Step Instructions

### 1. Git Status

Check current git state:

```bash
echo "=== Git Status ==="
git status --short
echo ""
git log --oneline -5
```

**Output Shows**:
- Modified files (M)
- Untracked files (??)
- Staged files (A)
- Recent commits

### 2. Current Branch

```bash
echo "=== Current Branch ==="
git branch --show-current
echo ""
echo "=== Remote Status ==="
git status -sb
```

**Output Shows**:
- Active branch name
- Commits ahead/behind remote

### 3. Active Work

Display current work from agent coordination:

```bash
echo "=== Active Tasks ==="
grep -A 20 "## Active Tasks" .agent/CURRENT_WORK.md | head -25
```

**Output Shows**: Current tasks being worked on

### 4. Module Count

Count modules by category:

```bash
echo "=== Module Inventory ==="
echo "Infrastructure (AWS): $(find infra/aws -name "module.json" | wc -l | tr -d ' ')"
echo "Infrastructure (Azure): $(find infra/azure -name "module.json" 2>/dev/null | wc -l | tr -d ' ')"
echo "Infrastructure (GCP): $(find infra/gcp -name "module.json" 2>/dev/null | wc -l | tr -d ' ')"
echo "Kubernetes: $(find k8s -name "module.json" | wc -l | tr -d ' ')"
echo "BNK: $(find bnk -name "module.json" -not -path "*/archived/*" | wc -l | tr -d ' ')"
echo "Archived: $(find archived -name "module.json" | wc -l | tr -d ' ')"
```

**Output Shows**: Number of modules in each category

### 5. Recent Changes

Check what files were recently modified:

```bash
echo "=== Recently Modified Files ==="
git log --name-only --pretty=format: --since="7 days ago" | sort | uniq | head -10
```

**Output Shows**: Files changed in the last week

### 6. Pending Work

Show top priority items from backlog:

```bash
echo "=== Top Priority Backlog Items ==="
grep -A 5 "## P0 - Critical" .agent/BACKLOG.md | head -10
grep -A 5 "## P1 - High Priority" .agent/BACKLOG.md | head -10
```

**Output Shows**: High-priority work items

## Example Output

```
=== Git Status ===
M .agent/CURRENT_WORK.md
?? infra/azure/

 8fb9479 Merge pull request #12
 191d818 Merge pull request #11
 fe77af5 ⚡ Bolt: optimize network interface polling

=== Current Branch ===
main

=== Remote Status ===
## main...origin/main

=== Active Tasks ===
### Setting Up Multi-Agent Workflow (2026-01-18)
Status: In Progress
...

=== Module Inventory ===
Infrastructure (AWS): 5
Infrastructure (Azure): 0
Infrastructure (GCP): 0
Kubernetes: 2
BNK: 7
Archived: 5

=== Recently Modified Files ===
.agent/CLAUDE.md
.agent/CURRENT_WORK.md
infra/aws/high-performance-nodes/scripts/dpdk-setup.sh

=== Top Priority Backlog Items ===
### Security & Stability
**None currently**
```

## Interpreting the Status

### Clean Repository
```
nothing to commit, working tree clean
```
= Ready for new work

### Modified Files
```
M .agent/CURRENT_WORK.md
M infra/aws/vpc/main.tf
```
= Work in progress, review changes before committing

### Untracked Files
```
?? infra/azure/
```
= New files/directories not yet added to git

### Behind Remote
```
## main...origin/main [behind 3]
```
= Need to pull changes from remote

### Ahead of Remote
```
## main...origin/main [ahead 2]
```
= Local commits not pushed to remote

## Quick Actions Based on Status

**If clean**: Start new work from backlog

**If modified files**: Review changes with `git diff`, commit if ready

**If untracked files**: Decide to add or ignore them

**If behind remote**: Pull changes with `git pull`

**If ahead of remote**: Push changes with `git push` (if ready)

## Related

- `.agent/CURRENT_WORK.md` - Detailed active work
- `.agent/BACKLOG.md` - Full backlog
- `/validate` - Validate repository health
