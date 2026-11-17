# Deployment Scripts & Git Hooks - Project Context & Architecture Guide

> [!NOTE]
> **AI Context Reference**: This document serves as the high-density architectural and domain guide for AI assistants (Antigravity, Cursor, Claude Code, Copilot) and developers. Read this before modifying or exploring the codebase.

---

## 1. Project Overview & Business Domain

- **Project Key**: `scripts`
- **Composer / Package**: `None (Shell Automation)`
- **Repository Type**: DevOps / Server Automation
- **Core Purpose**: The scripts repository contains the automated bare Git repository deployment pipeline and server orchestration suite used across TradifyLabs applications. It provides `bare-repo-deploy.sh` and the `post-receive` Git hook script, enabling automated zero-downtime server deployments, environment configuration linking, dependency installation, database migrations, asset compilation, and supervisor/queue worker reloading upon `git push`.

---

## 2. Architecture & Tech Stack

| Component | Specification |
| :--- | :--- |
| **Backend Framework** | Bash / Shell scripting, Linux systemd, Git hooks |
| **Frontend Engine** | N/A |
| **Database & Cache** | N/A |
| **Auth & Permissions** | SSH key-based Git authentication |

---

## 3. Core Domain Entities & Database Models

_No database models in this repository (DevOps / automation suite)._

---

## 4. User Roles, Panels & Route Structure

_No HTTP routes defined in this repository._

---

## 5. Key Integrations & Third-Party Services

- Git bare repositories with automated `post-receive` triggers
- Systemd / Supervisor queue worker restart signals
- Composer and NPM automated production deployment hooks

---

## 6. Development Workflow & Operational Commands

```bash
# View deployment script options and usage
bash bare-repo-deploy.sh --help

# Trigger automated post-receive deployment hook
git push production main
```

---

## 7. AI Assistant Guidelines & Code Conventions

- Ensure all shell scripts maintain POSIX compliance and safe error handling (`set -e`).
- Never commit live credentials, API keys, or server secrets to deployment scripts.
- Always test hook changes against a non-production repository before deployment.
