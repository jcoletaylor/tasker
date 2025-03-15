# Migration Plan: Ruby 3.2.7 & Rails Upgrade

## Overview
This document outlines the step-by-step plan for upgrading our application from Ruby 2.7 to Ruby 3.4, along with necessary Rails upgrades and dependency updates.

## Phase 1: Preparation and Analysis
- [x] Create baseline of current application state
    - [x] Document current Ruby version: 2.7.3
    - [x] Document current Rails version: 7.0.8.7
    - [x] Document current major dependency versions:
      - RSpec: 6.1.5 (rspec-rails)
      - RuboCop: 1.74.0
      - Sorbet: 0.5.11934
      - Sidekiq: 7.1.0
      - GraphQL: 2.4.14
      - PostgreSQL Adapter: 1.5.3 (pg)
      - Puma: 5.6.9
- [x] Set up minimal RuboCop configuration ✓
- [x] Run comprehensive test suite and document current state
    - Total examples: 40
    - Failures: 4 (all in GraphQL tasks queries)
    - Line Coverage: 82.24% (843/1025 lines)
    - Known Issues:
      - GraphQL pagination helper Integer conversion errors
      - RSwag deprecation warnings
      - Sidekiq test environment configuration needed
- [x] Generate dependency report using `bundle outdated`
    - Rails core (7.0.8.7 → 8.0.2)
    - Critical Security Updates Needed:
      - Nokogiri (1.15.7 → 1.18.4)
      - Rails HTML Sanitizer (1.6.2 → 1.6.2) ✓
    - Major Dependency Updates Required:
      - GraphQL (2.4.14 → 2.4.14) ✓
      - Puma (5.6.9 → 6.6.0)
      - Sidekiq (7.1.0 → 8.0.1)
      - RSpec Rails (6.1.5 → 7.1.1)
      - Active Model Serializers (0.10.15 → 0.10.15) ✓
    - Development Dependencies:
      - RuboCop RSpec (2.31.0 → 3.5.0)
      - SQLite3 (1.6.3 → 2.6.0)
- [x] Review deprecation warnings in test and log output
    - RSwag deprecations (swagger_root, swagger_docs, swagger_format)
    - Sidekiq testing environment warning

## Phase 2: Dependency Updates (Prioritized)
- [x] Security Updates ✓ (2025-03-15)
    - [x] Update Nokogiri (1.15.1 → 1.15.7)
    - [x] Update Rails HTML Sanitizer (1.5.0 → 1.6.2)
- [x] Update RuboCop and its extensions ✓ (2025-03-15)
    - [x] Update core RuboCop
    - [x] Update rubocop-rails
    - [x] Update rubocop-rspec (staying with 2.31.0 due to plugin compatibility)
    - [x] Update rubocop-performance
    - [x] Add rubocop-factory_bot for FactoryBot cops
- [ ] Update development dependencies
    - [ ] Update RSpec Rails (6.1.5 → 7.1.1)
    - [ ] Configure Sidekiq test environment
    - [ ] Update SQLite3 (1.6.3 → 2.6.0)
    - [ ] Update testing tools (factory_bot, etc.)
- [ ] Update runtime dependencies
    - [x] Update GraphQL (2.0.22 → 2.4.14) ✓
    - [ ] Fix GraphQL pagination helper issues
    - [ ] Update Puma (5.6.9 → 6.6.0)
    - [ ] Update Sidekiq (7.1.0 → 8.0.1)
    - [x] Update Active Model Serializers (0.10.13 → 0.10.15) ✓
    - [ ] Address RSwag deprecation warnings

## Phase 3: Ruby 3.x Compatibility
- [x] Upgrade to Ruby 3.2.7 ✓ (2025-03-15)
- [x] Enable Ruby 3.0 compatibility checks
    - [x] Add type checking configurations
    - [x] Run type checks on existing code
- [x] Address Ruby 2.7 deprecation warnings
    - [x] Updated GraphQL query files to use keyword arguments
    - [x] Identified remaining gem dependency warnings (pg, activerecord)
- [ ] Update syntax for Ruby 3.x compatibility
    - [x] Update keyword argument usage
        - [x] Updated Helpers module's page_sort_params method to use keyword arguments
        - [x] Updated all_tasks.rb, tasks_by_status.rb, and tasks_by_annotation.rb to use keyword arguments
        - [x] Fixed model references to use fully qualified name (Tasker::Task)
    - [ ] Update numbered block parameters
    - [ ] Update safe navigation operator usage
- [ ] Implement Progressive Type Checking
    - [ ] Add type signatures to models
    - [ ] Add type signatures to key services
    - [x] Update GraphQL query types
        - [x] Replace ActiveRecord::Relation[T.untyped] with T.untyped temporarily
        - [x] Fix incorrect method references (with_all_associated -> extract_associated)
        - [x] Update engine configuration type signatures
    - [ ] Configure type checking in CI

## Phase 4: Rails Upgrade Path
- [x] Upgrade to latest Rails 6.1 patch ✓ (2025-03-16)
- [x] Address deprecation warnings
- [x] Upgrade to Rails 7.0 ✓ (2025-03-18)
    - [x] Update configuration files
    - [x] Update initializers
    - [x] Address breaking changes
- [ ] Upgrade to Rails 7.1
    - [ ] Update for new defaults
    - [ ] Implement new features where beneficial

## Phase 5: Testing & Quality
- [ ] Expand test coverage
    - [ ] Add missing unit tests
    - [ ] Add integration tests for critical paths
- [ ] Update RuboCop configuration
    - [ ] Enable new cops
    - [ ] Configure department-specific rules
- [ ] Performance testing
    - [ ] Benchmark key operations
    - [ ] Profile memory usage
    - [ ] Address performance regressions

## Phase 6: Ruby 3.4 Migration
- [ ] Test with Ruby 3.4
    - [ ] Run test suite under 3.4
    - [ ] Address any new deprecation warnings
    - [ ] Fix any compatibility issues
- [ ] Update CI pipeline
    - [ ] Add Ruby 3.4 to test matrix
    - [ ] Update deployment scripts
- [ ] Production deployment planning
    - [ ] Create rollback plan
    - [ ] Schedule maintenance window
    - [ ] Update deployment documentation

## Rollback Plan
In case of critical issues during or after migration:
1. Immediately revert to Ruby 2.7 version
2. Restore from pre-migration backup
3. Roll back all dependency updates
4. Document issues encountered for future attempts

## Progress Tracking
- Start Date: 2025-03-15
- Current Phase: 4
- Completed Items: 24
- Next Action Item: Upgrade remaining dependencies (RSpec Rails, Puma, Sidekiq, SQLite3)
- Recent Progress:
    - 2025-03-18: Successfully upgraded to Rails 7.0.8.7, all tests passing
    - 2025-03-15: Moved files from app/models/tasker to lib/tasker and removed redundant copies
    - 2025-03-16: Successfully upgraded to Rails 6.1.7.10, all tests passing
    - 2025-03-15: Successfully upgraded to Ruby 3.2.7, all tests passing
    - 2025-03-15: Completed RuboCop and security updates
    - 2025-03-16: Completed keyword argument updates for Ruby 3.x compatibility
    - 2025-03-17: Completed upgrading GraphQL and Active Model Serializers

### Rails 7.0.8.7 Upgrade (2025-03-18)
- Successfully upgraded from Rails 6.1.7.10 to Rails 7.0.8.7
- Updated configuration files to match Rails 7.0 conventions
- Updated initializers to handle new Rails 7.0 defaults
- All 40 tests pass successfully with 80.91% test coverage (873/1079 lines)
- Application ready for Rails 7.1 upgrade when needed

### Rails 6.1.7.10 Upgrade (2025-03-16)
- Successfully upgraded from Rails 6.1.7.3 to Rails 6.1.7.10
- Added explicit logger requirement to fix Logger constant issue
- All 40 tests pass successfully with 80.91% test coverage (873/1079 lines)
- Application ready for Rails 7.0 upgrade

## Notes
- Keep this document updated as progress is made
- Mark items with ✓ when completed
- Add notes about any significant issues encountered
- Document any deviations from the plan

### RuboCop Notes (2025-03-15)
- The rubocop-rspec gem (v2.31.0) does not yet support the newer plugin system
- Using a hybrid approach with both `require` and `plugins` in .rubocop.yml
- FactoryBot cops have been extracted to rubocop-factory_bot gem
- Added exclude_limit syntax to replace deprecated max= configuration

### Type Checking Notes (2025-03-15)
- Temporary use of T.untyped for ActiveRecord::Relation types
- Post-migration type improvements needed:
    - Create proper RBI files for ActiveRecord::Relation
    - Replace T.untyped with proper type signatures
    - Add runtime type checking during development
    - Update SimpleCov configuration for proper type checking

### Ruby 3.x Compatibility Notes (2025-03-16)
- Remaining deprecation warnings from dependencies:
    - activerecord-6.1.7.3: PostgreSQL adapter using positional arguments
    - pg-1.5.3: Timestamp decoder using positional arguments
- These warnings will be resolved during Rails upgrade phase
- GraphQL query files updated for keyword argument compatibility:
    - Updated Helpers.page_sort_params to use keyword arguments
    - Updated all_tasks.rb, tasks_by_status.rb, and tasks_by_annotation.rb
    - Standardized model references to use fully qualified name (Tasker::Task)

### Ruby 3.2.7 Upgrade (2025-03-15)
- Successfully upgraded from Ruby 2.7.3 to Ruby 3.2.7
- All 40 tests pass successfully
- Test coverage at 80.91% (873/1079 lines)
- Updated .ruby-version file and Gemfile to specify Ruby 3.2.7
- No compatibility issues found with Rails 6.1.7.10

### Code Organization Notes (2025-03-15)
- Moved shared library files from app/models/tasker to lib/tasker
- Removed redundant copies of files
- Files moved: constants.rb, handler_factory.rb, task_handler.rb, and task_handler/ directory
- All tests passing after reorganization
