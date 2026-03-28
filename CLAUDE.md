AGENTS.md

## Quality Gates

Run all checks before committing. Fix any issues before creating the commit.

### 1. RuboCop (style)
```bash
bin/rubocop
```
Auto-fix safe offenses with `bin/rubocop -a`. Only run `-A` (unsafe autocorrect) if you understand the fix.

### 2. Bundler Audit (gem security)
```bash
bin/bundle-audit check --update
```
Flags gems with known CVEs. Do not ignore findings without explicit approval.

### 3. Importmap Audit
```bash
bin/rails importmap:audit
```
Checks JavaScript dependencies pinned via importmap for vulnerabilities.

### 4. Brakeman (security scan)
```bash
bin/brakeman -q --no-pager
```
Static analysis for security vulnerabilities (SQL injection, XSS, etc). All warnings must be addressed or acknowledged before committing.

### 5. Application tests
```bash
bin/rails test
```
All tests must pass. Do not commit with failing tests.

### 6. System tests
```bash
bin/rails test:system
```
Run if system tests exist. Skip if no system tests are present yet.
