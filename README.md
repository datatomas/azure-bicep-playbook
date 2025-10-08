# azure-bicep-playbook

Visit the Medium Article:
**https://help.medium.com/hc/en-us/categories/200058025-Writing
**

Azure Bicep Playbook — Production-grade IaC for “everything Azure”

A curated collection of production-ready Bicep modules and runnable examples that showcase secure, policy-compliant deployments across core Azure services. Opinionated defaults (tags, RBAC, diagnostics, private endpoints, DNS, identities) help you spin up real-world architectures fast—while staying readable, modular, and CI/CD-friendly.

What you’ll find

Reusable modules for networking, web, data, AI, security, and observability

Private networking patterns: generic Private Endpoint module + DNS wiring

Security baked-in: AAD-only where applicable, publicNetworkAccess = Disabled, managed identities, role assignments

Diagnostics everywhere: easy hooks to Log Analytics & diagnostic settings

Examples per scenario: web app with PE, AKS foundation, Doc Intelligence private, hub-spoke secure

Environment overlays: dev/test/prod via clean *.parameters.json

DX: simple WSL runners, what-if previews, GitHub Actions/Azure DevOps templates

Why it’s useful

Demonstrates real enterprise patterns without bloated templates

Teaches how to structure Bicep repos for scale: modules, examples, params, runners

Acts as a living reference for Azure architects and platform engineers

Who it’s for

Cloud engineers who want copy-pasteable patterns

Teams standardizing IaC with Bicep + CI/CD

Anyone preparing for secure, private-only Azure deployments
