---
name: implement-story
description: Implements a User Story from the backlog. Use when the user asks to implement a US (e.g. "implement US-06"). Reads the story, follows acceptance criteria, and uses the project's DDD structure.
argument-hint: "[story-number]"
---

# Implement User Story

You will implement User Story **US-$ARGUMENTS**.

## Step 1 — Context

Read the following files to understand the context:
- `docs/user-stories/$ARGUMENTS*.md` (use glob to find the exact file)
- `CLAUDE.md` for conventions and project structure

## Step 2 — Planning

Before coding, present to the user:
1. Which files will be created/modified
2. Which domain entities/value objects are involved
3. Which dependencies need to be installed (if any)
4. Estimated number of files to create

Wait for user confirmation before proceeding.

## Step 3 — Implementation

Follow the project's DDD structure (see CLAUDE.md):

```
src/<module>/
├── domain/           # Entities, Value Objects, repository interfaces
├── application/      # Services, Use Cases
└── infrastructure/   # Controllers, DTOs, Prisma repository implementation
```

Rules:
- Use the ubiquitous language defined in CLAUDE.md (OrdemDeServico, Produto, etc.)
- Domain validations in Value Objects (CPF/CNPJ, Placa, etc.)
- OS status as enum: RECEBIDA, EM_DIAGNOSTICO, AGUARDANDO_APROVACAO, EM_EXECUCAO, FINALIZADA, ENTREGUE, CANCELADA
- Controllers with Swagger decorators
- DTOs with class-validator
- Register the module in app.module.ts

## Step 4 — Prisma Schema

If the story requires new tables:
1. Add models to `prisma/schema.prisma`
2. Generate migration: `npx prisma migrate dev --name <description>`

## Step 5 — Verification

- Run `npx tsc --noEmit` to check compilation
- If tests are required by acceptance criteria, implement them
- List acceptance criteria met vs pending

## Step 6 — Summary

At the end, present:
- Files created/modified
- Acceptance criteria met (checklist)
- Next steps or dependencies with other stories
