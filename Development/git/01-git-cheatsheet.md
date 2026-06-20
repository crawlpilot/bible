# Git Cheatsheet — Principal Engineer Depth

> Goal: not just what commands do, but _when to use them_ and _what to say in an interview_ when asked about a Git-related war story.

---

## 1. Mental Model: Plumbing vs Porcelain

Git is a content-addressed object store. Every porcelain command (commit, merge, rebase) is sugar over four object types:

| Object | What it stores | Command to inspect |
|--------|---------------|--------------------|
| **blob** | File contents (no name, no path) | `git cat-file -p <hash>` |
| **tree** | Directory listing (name → blob/tree hash) | `git ls-tree HEAD` |
| **commit** | Tree hash + parent(s) + author + message | `git cat-file commit HEAD` |
| **tag** | Annotated pointer to a commit | `git cat-file tag v1.0` |

**Why this matters in interviews:** When you explain why `git rebase` rewrites history (new commit hashes) vs `git merge` (preserves them), you're reasoning from this model. Merge creates a new commit with two parents. Rebase replays commits on top of a new base, producing new SHA1s — that's why force-pushing a rebased branch is dangerous on shared branches.

---

## 2. Daily Commands — With the Why

### Staging and Committing

```bash
# Stage hunks interactively — lets you split a logical change into clean commits
git add -p

# Amend the last commit (only safe before pushing)
git commit --amend --no-edit        # keep same message
git commit --amend -m "new message"

# Create an empty commit (useful for triggering CI)
git commit --allow-empty -m "trigger build"
```

### Branching

```bash
# Create and switch (modern syntax)
git switch -c feature/my-feature

# Delete a branch locally and remotely
git branch -d feature/done
git push origin --delete feature/done

# Rename current branch
git branch -m new-name

# List branches sorted by last commit
git branch --sort=-committerdate
```

### Viewing History

```bash
# One-line graph (alias this as `git lg`)
git log --oneline --graph --decorate --all

# Show what changed in a commit
git show <hash>

# Who last touched each line
git blame -L 42,60 src/Service.java

# Find which commit introduced a string
git log -S "ConnectionPool" --oneline

# All commits that touched a file
git log --follow -- path/to/file.java
```

### Searching and Debugging

```bash
# Binary search for a regression
git bisect start
git bisect bad                      # current commit is broken
git bisect good v2.3.1              # last known good tag
# Git checks out midpoints; you run tests and mark good/bad
git bisect good                     # or: git bisect bad
git bisect reset                    # when done

# Find which commit deleted a function
git log --all -S "myFunction" --oneline -- "*.java"

# Search commit messages
git log --grep="OOM" --oneline
```

### Undoing Changes

```bash
# Discard uncommitted changes to a file
git restore path/to/file.java

# Unstage a file
git restore --staged path/to/file.java

# Undo last commit, keep changes staged
git reset --soft HEAD~1

# Undo last commit, keep changes unstaged
git reset --mixed HEAD~1            # default

# Nuclear: discard last commit and all changes
git reset --hard HEAD~1             # DANGEROUS — loses work

# Safe undo: create a reverting commit (safe for shared branches)
git revert HEAD
git revert <hash>

# Recover a dropped commit via reflog
git reflog                          # find the hash
git cherry-pick <recovered-hash>
```

> **Reflog is your safety net.** Git keeps a local reflog of every HEAD movement for ~90 days. Even after `reset --hard`, you can recover commits:
> ```bash
> git reflog
> # HEAD@{3}: commit: the commit you lost
> git cherry-pick HEAD@{3}
> ```

### Stashing

```bash
git stash push -m "WIP: fixing auth bug"
git stash list
git stash pop                       # apply and drop top
git stash apply stash@{2}          # apply without dropping
git stash drop stash@{2}
git stash branch fix/from-stash    # create branch from stash
```

---

## 3. Rebase — The Power Tool

### Interactive Rebase

```bash
# Rewrite last 5 commits
git rebase -i HEAD~5
```

Commands available in the editor:

| Command | What it does |
|---------|-------------|
| `pick` | Keep commit as-is |
| `reword` | Keep commit, edit message |
| `edit` | Pause to amend the commit |
| `squash` | Meld into previous commit, combine messages |
| `fixup` | Meld into previous commit, discard this message |
| `drop` | Delete the commit |
| `exec` | Run a shell command after this line |

**When to squash:** Before merging a feature branch — combine WIP commits into logical units. Most FAANG teams enforce squash merges via GitHub/GitLab settings.

**When NOT to rebase:** On a branch that other engineers have pulled. Rewriting shared history forces a force-push, which diverges everyone's local branch. Rule: **never rebase branches with collaborators unless the team has an explicit agreement.**

### Rebase vs Merge — The Real Trade-off

| | Merge | Rebase |
|--|-------|--------|
| History | Preserves exact branch topology | Linear, easier to read |
| SHA1s | Parent commits unchanged | New hashes for replayed commits |
| Conflicts | Resolved once | Resolved per-replayed-commit |
| Shared branches | Safe | Dangerous (rewrites history) |
| Bisect friendliness | Harder (merge commits clutter) | Cleaner |
| FAANG preference | Meta/Google prefer squash+merge | Trunk-based teams often rebase locally then squash |

---

## 4. Cherry-Pick

```bash
# Apply a specific commit to current branch
git cherry-pick <hash>

# Apply a range (exclusive start, inclusive end)
git cherry-pick abc123..def456

# Apply but don't commit yet (stage only)
git cherry-pick -n <hash>

# Continue after resolving conflicts
git cherry-pick --continue
git cherry-pick --abort
```

**When cherry-pick is appropriate:** Hotfix that was first merged to main but also needed on a release branch. Avoid using it as a substitute for proper branching — it creates duplicate commits with different SHAs and can cause confusing merge conflicts later.

---

## 5. Tags

```bash
# Lightweight tag (just a pointer)
git tag v1.2.3

# Annotated tag (has its own object: tagger, date, message)
git tag -a v1.2.3 -m "Release 1.2.3 — add rate limiting"

# Push tags (not pushed by default)
git push origin v1.2.3
git push origin --tags              # push all tags

# Delete a tag
git tag -d v1.2.3
git push origin --delete v1.2.3

# List tags matching a pattern
git tag -l "v1.2.*"
```

**FAANG signal:** Annotated tags trigger release pipelines (GitHub Releases, npm publish). Lightweight tags are for local bookmarks. Always use annotated tags for releases.

---

## 6. Worktrees

Multiple working trees from the same repo — lets you work on two branches simultaneously without stashing or cloning twice.

```bash
# Add a worktree for a branch
git worktree add ../hotfix-branch hotfix/v2.3.1

# List all worktrees
git worktree list

# Remove a worktree
git worktree remove ../hotfix-branch
```

**Use case at FAANG scale:** You're mid-feature on main but a P0 fires. Instead of stashing or cloning, `git worktree add` gives you a second checkout in seconds, sharing the same object store (no extra disk usage for history).

---

## 7. Submodules vs Subtrees

| | Submodule | Subtree |
|--|-----------|---------|
| Mechanism | Pointer to a commit in another repo | History merged/copied into this repo |
| Checkout | `git submodule update --init` required | Just works |
| Updates | Must update pointer explicitly | `git subtree pull` |
| Complexity | Higher (two repos to manage) | Lower (one repo) |
| Use case | Shared library, separate lifecycle | Vendored dependency, simpler workflow |

Most FAANG teams migrating to monorepos use **subtree merge** or just copy the code and have a single source of truth.

---

## 8. Git Hooks

Located in `.git/hooks/` (local, not committed) or managed via `pre-commit` framework or Husky.

| Hook | Runs when | Common use |
|------|-----------|-----------|
| `pre-commit` | Before commit is created | Lint, format, unit tests |
| `commit-msg` | After message entered | Enforce Jira ticket format |
| `pre-push` | Before push | Run full test suite |
| `post-merge` | After merge/pull | Run `npm install` if package.json changed |
| `pre-receive` (server) | Before push accepted | Enforce signed commits, branch protection |

**Interview angle:** How do you enforce standards across 200 engineers? Git hooks are per-developer and skippable (`--no-verify`). Server-side hooks (GitHub branch protection + required status checks) are the real enforcement mechanism. Pre-commit hooks are DX, not security.

---

## 9. Large File Handling

```bash
# Git LFS — tracks large files as pointers
git lfs track "*.psd"
git lfs track "data/*.parquet"
git lfs ls-files

# Find large files that shouldn't be in git
git rev-list --objects --all | \
  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
  awk '/^blob/ { print $3, $4 }' | sort -n -r | head -20
```

---

## 10. Key Configuration

```bash
# Global identity
git config --global user.name "Rahul Bisht"
git config --global user.email "rahulbisht6365@gmail.com"

# Default branch name
git config --global init.defaultBranch main

# Rebase on pull (instead of merge)
git config --global pull.rebase true

# Auto-stash before rebase
git config --global rebase.autoStash true

# Better diff for word changes
git config --global diff.wordRegex .

# Useful aliases
git config --global alias.lg "log --oneline --graph --decorate --all"
git config --global alias.st "status -s"
git config --global alias.undo "reset --soft HEAD~1"
git config --global alias.fixup "commit --amend --no-edit"
```

---

## FAANG Interview Callouts

**"Tell me about a time you recovered from a git disaster"**
→ Story arc: someone force-pushed to main, CI broke. Recovery: `git reflog` on affected developer machines, identify the last good commit, `git push --force-with-lease origin main` to restore (after verifying with team). Then: add branch protection rules, require PRs, never allow force-push to main.

**"How do you keep a clean git history at scale?"**
→ Enforce squash-and-merge at the repo level (GitHub branch settings). Every PR = one commit on main. Feature flags decouple deployment from merge. Code review standards (see [01-code-review-standards.md](../best-practices/01-code-review-standards.md)) define commit message conventions.

**"How does git rebase work under the hood?"**
→ Git replays each commit from the branch onto the new base. For each commit: applies the diff as a patch to the new base, creates a new commit object with a new parent and new SHA1. The old commits remain until GC. This is why rebasing changes history — same content, different identity.
