## Plan: Rocky 8 Compatibility Migration

Transform the current Debian-focused automation into Rocky 8-first automation with full parity (core provisioning, databases, runtimes, and both web stacks), while removing Debian-specific assumptions across scripts and docs. The safest approach is to introduce a shared OS/package abstraction first, then migrate installers in dependency order, and finish with Rocky validation on WSL2.

**Steps**
1. Phase 1: Baseline and compatibility contract.
2. Confirm Rocky 8-only support contract in project docs and script headers, and remove Debian-first wording in onboarding entry points. This prevents ambiguous behavior while migration is in progress.
3. Define a compatibility contract document for package manager, service manager, package-query method, repository layout, user/group mapping, and config path mapping specific to Rocky 8.
4. Phase 2: Shared platform abstraction layer (*blocks phases 3-6*).
5. Add shared helper functions in shell libraries for: package install/update/query, repo registration, service enable/start/restart, package existence checks, and OS metadata reads from /etc/os-release.
6. Replace direct apt/apt-get/apt-cache/dpkg-query usage in orchestrators with helper calls so downstream scripts inherit Rocky-safe behavior.
7. Normalize logging/build artifact directory naming from Debian-specific paths to distro-neutral naming used everywhere.
8. Phase 3: Core orchestrators and bootstrap migration (*depends on phase 2*).
9. Update bootstrap entry scripts to use Rocky 8 base package set and remove Debian-only packages (for example apt-transport-https semantics).
10. Ensure top-level flow fails fast with a clear message if a non-Rocky distro is detected (Rocky-only scope), rather than attempting partial execution.
11. Verify wizard/init/run paths consume new helper layer and no direct apt/dpkg calls remain in top-level scripts.
12. Phase 4: Service installer migration (*parallelizable by component after phase 2*).
13. Database installers: migrate MariaDB, PostgreSQL, MongoDB installers to Rocky repo + dnf flows; replace dpkg-query logic with rpm query checks; update version/package fallback logic for Rocky repos.
14. Cache/runtime installers: migrate Redis, Python, Java, Node/Tomcat scripts to Rocky package/repo/service conventions, preserving current environment-variable controls.
15. Web installers: migrate Apache and Nginx installers to Rocky package names and filesystem conventions; keep PHP-FPM integration working for both web servers under Rocky paths.
16. SSL helpers: migrate Apache/Nginx SSL helpers (mkcert install path, ownership groups, config targets) to Rocky conventions.
17. Phase 5: Apache and Nginx Rocky parity hardening (*depends on phase 4 web installers*).
18. Replace Debian-only Apache helper commands (a2enmod/a2enconf/a2ensite patterns) with Rocky-native config-file/module workflows under httpd directories.
19. Standardize Nginx site include layout for Rocky (/etc/nginx/conf.d) and validate PHP-FPM socket resolution via configurable variable with Rocky default.
20. Align service names and ownership groups (apache/nginx) in permissions and restart logic.
21. Phase 6: Docs and operator UX (*parallel with late phase 4/5 updates, finalized after validation*).
22. Rewrite onboarding docs to Rocky-first commands and examples, including prerequisite/update/install commands and known WSL2 Rocky notes.
23. Add a dedicated distro compatibility/reference document capturing command/path/package-name mappings and explicit non-goals.
24. Update quickstart and component docs so each script section reflects Rocky command behavior and expected outputs.
25. Phase 7: Verification and release readiness (*depends on phases 3-6*).
26. Static audit: ensure no apt/apt-get/apt-cache/dpkg-query/a2en* Debian-only calls remain in active Rocky paths.
27. Functional validation on fresh Rocky 8 WSL2: run init, wizard, and full run paths; then run representative component installs individually.
28. Service validation: verify active/enabled states and health checks for MariaDB, PostgreSQL, MongoDB, Redis, Apache, Nginx, PHP-FPM, and selected runtime stack.
29. Idempotency validation: re-run provisioning to confirm repeat-safe behavior and no destructive side effects.
30. Log and fix blockers, then re-run validation until clean pass criteria are met.

**Relevant files**
- /home/aqjRocky/serverProvo/begin_here.sh — bootstrap package list, distro assumptions, log path naming.
- /home/aqjRocky/serverProvo/provisioning.sh — orchestration flow, base packages, helper integration points.
- /home/aqjRocky/serverProvo/scripts/mariadb_install.sh — dnf migration, service/package checks.
- /home/aqjRocky/serverProvo/scripts/postgresql_install.sh — rpm-query checks and Rocky package/version fallback logic.
- /home/aqjRocky/serverProvo/scripts/mongodb_install.sh — Rocky-compatible repo logic and package detection.
- /home/aqjRocky/serverProvo/scripts/redis_install.sh — package install/query migration and service behavior.
- /home/aqjRocky/serverProvo/scripts/python_install.sh — package manager abstraction replacement for apt-only flow.
- /home/aqjRocky/serverProvo/scripts/web_server_apache_install.sh — apache2 to httpd migration and module/config workflow rewrite.
- /home/aqjRocky/serverProvo/scripts/web_server_nginx_install.sh — Rocky path defaults and php-fpm integration checks.
- /home/aqjRocky/serverProvo/scripts/lib/apache_ssl.sh — Rocky Apache SSL paths, ownership, enable flow.
- /home/aqjRocky/serverProvo/scripts/lib/nginx_ssl.sh — Rocky Nginx SSL install/ownership/path updates.
- /home/aqjRocky/serverProvo/scripts/lib/java_stack.sh — Rocky repo/package conventions for Java distributions.
- /home/aqjRocky/serverProvo/scripts/lib/php_web.sh — Rocky PHP repo/package naming and install logic.
- /home/aqjRocky/serverProvo/scripts/lib/database.sh — shared DB checks and distro-safe package/service helpers.
- /home/aqjRocky/serverProvo/README.md — Rocky-first project framing and quickstart.
- /home/aqjRocky/serverProvo/docs/00-QUICKSTART.md — Rocky quickstart commands.
- /home/aqjRocky/serverProvo/docs/01-SETUP.md — Rocky target environment/setup assumptions.
- /home/aqjRocky/serverProvo/docs/04-WEB-STACK.md — Rocky Apache/Nginx/PHP behavior.
- /home/aqjRocky/serverProvo/docs/05-DATABASES.md — Rocky DB installation semantics.
- /home/aqjRocky/serverProvo/docs/07-WSL-NOTES.md — Rocky WSL2 service/runtime caveats.

**Verification**
1. Run a repository-wide search and confirm Debian-only commands are removed from Rocky execution paths: apt, apt-get, apt-cache, dpkg-query, a2enmod, a2enconf, a2ensite.
2. Execute bootstrap flow on fresh Rocky 8 WSL2: begin_here + provisioning init + provisioning wizard + provisioning run.
3. Execute component scripts directly for targeted validation: mariadb, postgresql, mongodb, redis, apache, nginx, python, java stack, tomcat.
4. Validate service health via systemctl status and functional probes (for example, DB client connect checks, web server config tests, HTTP endpoint checks).
5. Re-run full provisioning to confirm idempotency.
6. Review logs in normalized provisioning log directory and resolve any failing steps; re-test until no failures remain.

**Decisions**
- Support scope: Rocky 8 only (no Debian backward compatibility requirement in this migration).
- Feature scope: include both Apache and Nginx support in this migration.
- Runtime scope: full parity required, including Java/PHP/MongoDB compatibility.
- Included: script orchestration, component installers, helper libraries, and documentation.
- Excluded: support for non-Rocky RPM distros unless explicitly requested later.

**Further Considerations**
1. Rocky package source strategy for PHP and MongoDB should be fixed early (distribution repos vs third-party repos) because it drives implementation details in multiple scripts.
2. Decide whether to keep a compatibility shim layer for potential future multi-distro support or simplify aggressively for Rocky-only maintenance.
3. Add a lightweight CI smoke path (container or VM-based) for Rocky 8 to prevent regression after migration.