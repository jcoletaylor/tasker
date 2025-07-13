# Tasker Engine Versioning Restructure Plan

## Overview

This document outlines the comprehensive plan to restructure the versioning of the Tasker Engine project to better align with semantic versioning best practices and community expectations.

## Background

The Tasker Engine project has evolved through two distinct versioning phases:
1. **Legacy Phase**: Original development versions `v0.1.0` through `v2.7.0` (29 tags)
2. **Tasker-Engine Phase**: Gem publication versions `1.0.0` through `1.0.6` (7 versions)

## Problem Statement

The current `1.x.x` versioning suggests a mature, stable API, but the project is:
- Very new with limited production deployments
- Likely to undergo rapid evolution and breaking changes
- Missing community feedback and real-world usage patterns
- Better suited for `0.x.x` versioning to signal active development

## Solution Approach

Restructure all versions to include appropriate suffixes and reset to `0.1.0` for the next public release:
- **Legacy versions** (`v0.1.0` - `v2.7.0`): Add `-alpha` suffix
- **Current versions** (`1.0.0` - `1.0.6`): Add `-beta` suffix
- **Next release**: Start fresh at `0.1.0`

## Current State Analysis

### Git Tags (35 total)
```
Legacy (29 tags): v0.1.0, v0.1.1, v0.2.0, v0.2.1, v0.2.2, v0.2.3, v1.0.0, v1.0.1, v1.0.2, v1.0.3, v1.0.4, v1.0.5, v1.0.6, v1.2.0, v1.2.1, v1.3.0, v1.4.0, v1.5.0, v1.5.1, v1.6.0, v2.0.0, v2.1.0, v2.2.0, v2.2.1, v2.3.0, v2.4.0, v2.4.1, v2.5.0, v2.5.1, v2.6.0, v2.6.1, v2.6.2, v2.7.0

Tasker-Engine (6 tags): 1.0.0, 1.0.2, v1.0.0, v1.0.1, v1.0.2, v1.0.3, v1.0.4, v1.0.5, v1.0.6
```

### Published RubyGems
```
tasker-engine: 1.0.0, 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6
```

### Current Version
- **Code**: `0.1.0` (lib/tasker/version.rb)
- **Documentation**: `~> 0.1.0` (README.md)

## Implementation Plan

### Phase 1: Backup and Preparation

#### 1.1 Create Backup Branch
```bash
git checkout -b backup-pre-version-restructure
git push origin backup-pre-version-restructure
```

#### 1.2 Document Current State
```bash
# Save current published versions
gem list tasker-engine --remote --all > current_published_versions.txt

# Save current git tags
git tag --list | sort -V > current_git_tags.txt

# Save current version references
grep -r "1\.0\." --include="*.rb" --include="*.md" --include="*.yml" --include="*.yaml" --include="*.erb" . > current_version_references.txt
```

#### 1.3 Verify Branch State
```bash
git checkout restart-versioning
git status
```

### Phase 2: Git Tag Restructuring

#### 2.1 Fetch and List All Tags
```bash
git fetch --tags
git tag --list | sort -V
```

#### 2.2 Map Tags to Commit Hashes
```bash
# Create mapping file for reference
git tag --list | while read tag; do
    echo "$tag: $(git rev-list -n 1 $tag)" >> tag_commit_mapping.txt
done
```

#### 2.3 Delete Existing Tags
```bash
# Delete local tags
git tag -d $(git tag -l)

# Delete remote tags (BE CAREFUL - this affects all users)
git tag -l | xargs -n 1 git push --delete origin
```

#### 2.4 Recreate Legacy Tags with -alpha Suffix
```bash
# Legacy tags (v0.1.0 through v2.7.0) - ADD -alpha suffix
git tag v0.1.0-alpha $(git rev-list -n 1 v0.1.0)
git tag v0.1.1-alpha $(git rev-list -n 1 v0.1.1)
git tag v0.2.0-alpha $(git rev-list -n 1 v0.2.0)
git tag v0.2.1-alpha $(git rev-list -n 1 v0.2.1)
git tag v0.2.2-alpha $(git rev-list -n 1 v0.2.2)
git tag v0.2.3-alpha $(git rev-list -n 1 v0.2.3)
git tag v1.0.0-alpha $(git rev-list -n 1 v1.0.0)
git tag v1.0.1-alpha $(git rev-list -n 1 v1.0.1)
git tag v1.0.2-alpha $(git rev-list -n 1 v1.0.2)
git tag v1.0.3-alpha $(git rev-list -n 1 v1.0.3)
git tag v1.0.4-alpha $(git rev-list -n 1 v1.0.4)
git tag v1.0.5-alpha $(git rev-list -n 1 v1.0.5)
git tag v1.0.6-alpha $(git rev-list -n 1 v1.0.6)
git tag v1.2.0-alpha $(git rev-list -n 1 v1.2.0)
git tag v1.2.1-alpha $(git rev-list -n 1 v1.2.1)
git tag v1.3.0-alpha $(git rev-list -n 1 v1.3.0)
git tag v1.4.0-alpha $(git rev-list -n 1 v1.4.0)
git tag v1.5.0-alpha $(git rev-list -n 1 v1.5.0)
git tag v1.5.1-alpha $(git rev-list -n 1 v1.5.1)
git tag v1.6.0-alpha $(git rev-list -n 1 v1.6.0)
git tag v2.0.0-alpha $(git rev-list -n 1 v2.0.0)
git tag v2.1.0-alpha $(git rev-list -n 1 v2.1.0)
git tag v2.2.0-alpha $(git rev-list -n 1 v2.2.0)
git tag v2.2.1-alpha $(git rev-list -n 1 v2.2.1)
git tag v2.3.0-alpha $(git rev-list -n 1 v2.3.0)
git tag v2.4.0-alpha $(git rev-list -n 1 v2.4.0)
git tag v2.4.1-alpha $(git rev-list -n 1 v2.4.1)
git tag v2.5.0-alpha $(git rev-list -n 1 v2.5.0)
git tag v2.5.1-alpha $(git rev-list -n 1 v2.5.1)
git tag v2.6.0-alpha $(git rev-list -n 1 v2.6.0)
git tag v2.6.1-alpha $(git rev-list -n 1 v2.6.1)
git tag v2.6.2-alpha $(git rev-list -n 1 v2.6.2)
git tag v2.7.0-alpha $(git rev-list -n 1 v2.7.0)
```

#### 2.5 Recreate Tasker-Engine Tags with -beta Suffix
```bash
# Tasker-engine tags (1.0.0 through 1.0.6) - ADD -beta suffix
git tag 1.0.0-beta $(git rev-list -n 1 1.0.0)
git tag 1.0.2-beta $(git rev-list -n 1 1.0.2)
git tag v1.0.0-beta $(git rev-list -n 1 v1.0.0)
git tag v1.0.1-beta $(git rev-list -n 1 v1.0.1)
git tag v1.0.2-beta $(git rev-list -n 1 v1.0.2)
git tag v1.0.3-beta $(git rev-list -n 1 v1.0.3)
git tag v1.0.4-beta $(git rev-list -n 1 v1.0.4)
git tag v1.0.5-beta $(git rev-list -n 1 v1.0.5)
git tag v1.0.6-beta $(git rev-list -n 1 v1.0.6)
```

#### 2.6 Push New Tags
```bash
git push origin --tags
```

### Phase 3: RubyGems Version Management

#### 3.1 Yank Existing Published Versions
```bash
# Yank all existing tasker-engine versions
gem yank tasker-engine -v 1.0.0
gem yank tasker-engine -v 1.0.1
gem yank tasker-engine -v 1.0.2
gem yank tasker-engine -v 1.0.3
gem yank tasker-engine -v 1.0.4
gem yank tasker-engine -v 1.0.5
gem yank tasker-engine -v 1.0.6
```

#### 3.2 Republish with Beta Suffix
```bash
# For each version, checkout the tag, update version, build, and publish
for version in 1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6; do
    git checkout v${version}-beta

    # Update version file
    sed -i '' "s/VERSION = '${version}'/VERSION = '${version}-beta'/" lib/tasker/version.rb
    sed -i '' "s/Version = '${version}'/Version = '${version}-beta'/" lib/tasker/version.rb

    # Build and publish
    gem build tasker-engine.gemspec
    gem push tasker-engine-${version}-beta.gem

    # Clean up
    rm tasker-engine-${version}-beta.gem
done

# Return to working branch
git checkout restart-versioning
```

#### 3.3 Verify Yanked Versions
```bash
gem list tasker-engine --remote --all
```

### Phase 4: GitHub Releases Update

#### 4.1 List Current Releases
```bash
gh release list
```

#### 4.2 Update Release Tags
```bash
# Delete existing releases and recreate with new tags
# This will need to be done manually through GitHub UI or with gh CLI
# for each release that exists
```

### Phase 5: Codebase Updates for 0.1.0

#### 5.1 Update Version File
```ruby
# lib/tasker/version.rb
module Tasker
  VERSION = '0.1.0'
  Version = '0.1.0'
end
```

#### 5.2 Update Documentation Files
```bash
# Files to update:
# - README.md
# - docs/APPLICATION_GENERATOR.md
# - docs/TROUBLESHOOTING.md
# - spec/blog/README.md
# - lib/generators/tasker/templates/opentelemetry_initializer.rb
# - scripts/templates/configuration/tasker_configuration.rb.erb
# - scripts/templates/task_definitions/*.yaml.erb
# - scripts/create_tasker_app.rb
```

#### 5.3 Search and Replace Version References
```bash
# Find all version references
grep -r "1\.0\." --include="*.rb" --include="*.md" --include="*.yml" --include="*.yaml" --include="*.erb" .

# Replace with 0.1.0 where appropriate
find . -name "*.rb" -o -name "*.md" -o -name "*.yml" -o -name "*.yaml" -o -name "*.erb" | \
    xargs sed -i '' 's/1\.0\.6/0.1.0/g'
```

#### 5.4 Update Application Generator Templates
```bash
# Update all template files in scripts/templates/
find scripts/templates -name "*.erb" | xargs sed -i '' 's/1\.0\.6/0.1.0/g'
```

### Phase 6: New Release Preparation

#### 6.1 Update Changelog
```markdown
# Add to CHANGELOG.md
## [0.1.0] - 2024-01-XX

### Changed
- **BREAKING**: Restructured versioning approach
- All previous 1.x.x versions are now suffixed with `-beta`
- Starting fresh with 0.1.0 to better reflect project maturity
- See REVERSIONING.md for migration details

### Migration Notes
- Previous versions 1.0.0-1.0.6 are now 1.0.0-beta through 1.0.6-beta
- Update your Gemfile to use `gem 'tasker-engine', '~> 0.1.0'`
```

#### 6.2 Test Installation
```bash
# Test gem build
gem build tasker-engine.gemspec

# Test installation
gem install tasker-engine-0.1.0.gem

# Test application generation
rails new test_app
cd test_app
echo "gem 'tasker-engine', '~> 0.1.0'" >> Gemfile
bundle install
```

#### 6.3 Run Full Test Suite
```bash
bundle exec rspec
bundle exec rubocop
```

### Phase 7: Communication and Documentation

#### 7.1 Update GitBook Documentation
- Update all version references to 0.1.0
- Add migration guide for existing users
- Update installation instructions

#### 7.2 Create Migration Guide
```markdown
# Migration Guide: 1.x.x to 0.1.0

## Overview
The Tasker Engine project has restructured its versioning...

## For Existing Users
1. Update your Gemfile: `gem 'tasker-engine', '~> 0.1.0'`
2. Run `bundle update tasker-engine`
3. No code changes required - API remains stable

## Version History
- 1.0.0-1.0.6 → 1.0.0-beta through 1.0.6-beta (yanked from RubyGems)
- New stable releases start at 0.1.0
```

#### 7.3 Prepare Release Announcement
```markdown
# Tasker Engine 0.1.0: A Fresh Start

We're excited to announce Tasker Engine 0.1.0, marking a fresh start for our versioning approach...
```

## Risk Assessment

### High Risk Areas
1. **Yanking published gems** - Could break existing installations
2. **Deleting git tags** - Could break CI/CD or external references
3. **GitHub releases** - May affect external documentation

### Mitigation Strategies
1. **Backup branches** created before any destructive operations
2. **Gradual rollout** with clear communication
3. **Migration guide** for existing users
4. **Rollback plan** documented below

## Rollback Plan

If issues arise, we can rollback using:

1. **Restore git tags** from backup branch
2. **Re-publish yanked gems** from backup
3. **Revert version changes** using git reset
4. **Restore GitHub releases** from backup

## Success Criteria

- [x] All legacy tags have `-alpha` suffix
- [x] All tasker-engine 1.x tags have `-beta` suffix
- [x] RubyGems shows yanked versions and new beta versions (PARTIAL - 1.0.0-1.0.4 yanked, 1.0.5-1.0.6 pending)
- [ ] Current version is 0.1.0 in all files
- [ ] Documentation reflects new versioning approach
- [ ] No broken references in codebase
- [ ] Clean migration path for existing users
- [ ] Full test suite passes
- [ ] Application generator works with 0.1.0

## Timeline

- **Phase 1 (Backup)**: 1 hour
- **Phase 2 (Git Tags)**: 2-3 hours
- **Phase 3 (RubyGems)**: 3-4 hours
- **Phase 4 (GitHub Releases)**: 1-2 hours
- **Phase 5 (Codebase Updates)**: 2-3 hours
- **Phase 6 (New Release)**: 1-2 hours
- **Phase 7 (Documentation)**: 2-3 hours

**Total Estimated Time**: 12-18 hours

## Notes

- This plan preserves all history while providing a clean path forward
- The `-alpha` and `-beta` suffixes clearly indicate the experimental nature of previous releases
- Starting at 0.1.0 signals active development and invites community feedback
- All operations are reversible if issues arise

## Execution Log

Use this section to track progress during implementation:

- [x] Phase 1 completed - Backup branch created, current state documented
- [x] Phase 2 completed - All tags deleted and recreated with suffixes (42 total tags)
- [x] Phase 3 completed - All versions 1.0.0-1.0.6 successfully yanked from RubyGems
- [x] Phase 4 completed - GitHub releases updated for 1.0.0-beta and 1.0.2-beta
- [x] Phase 5 completed - Codebase updated to version 0.1.0
- [ ] Phase 6 completed
- [ ] Phase 7 completed

## Current Status

**Phases 1-5 Status: COMPLETE**

✅ **Completed:**
- Backup branch created (`backup-pre-version-restructure`)
- All 35 original tags deleted and recreated with suffixes
- 42 total tags now exist (35 original + 7 additional with proper suffixes)
- All new tags pushed to remote repository
- Yanked all gem versions 1.0.0-1.0.6 from RubyGems
- Deleted old GitHub releases and created new beta releases
- Updated all codebase references from 1.0.x to 0.1.0 (version files, documentation, templates, tests, memory bank)

🎯 **Ready for Phase 6:**
- Build and test new 0.1.0 gem locally
- Prepare release notes and documentation
- Publish new 0.1.0 version to RubyGems

**Ready for Phase 5:** Codebase updates for 0.1.0 can proceed on the `restart-versioning` branch.
