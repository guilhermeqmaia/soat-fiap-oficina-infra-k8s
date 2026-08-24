---
name: qa-plan
description: Generates the QA_PLAN document for a User Story. Use after implementing a US to create the manual and automated test plan with instructions on how to validate each acceptance criterion.
argument-hint: "[story-number]"
---

# Generate QA Plan for User Story

You will generate the QA_PLAN document for **US-$ARGUMENTS**.

## Step 1 — Context

Read the following files:
- `docs/user-stories/$ARGUMENTS*.md` (use glob to find the exact file)
- `CLAUDE.md` to understand the domain and conventions
- Implemented code in `src/` related to this story (if it exists)

## Step 2 — Generate the QA_PLAN

Create the file `docs/qa-plans/QA_PLAN_US-$ARGUMENTS.md` with the following structure:

```markdown
# QA Plan — US-$ARGUMENTS: [story title]

## Summary
Brief description of what is being tested and the story's objective.

## Prerequisites
- Required environment (Docker, database, seeds, etc.)
- Required test data
- Specific configurations (.env, etc.)

## Test Scenarios

### TS-01: [scenario name]
- **Type:** Manual | Automated | Both
- **Acceptance criterion:** [reference to criterion]
- **Precondition:** [required initial state]
- **Steps:**
  1. [detailed step-by-step]
  2. ...
- **Expected result:** [what should happen]
- **Alternative result (error):** [what happens on failure]

### TS-02: ...
(repeat for each scenario)

## Edge Cases
- Boundary cases and invalid inputs to validate

## Validation Checklist
- [ ] All acceptance criteria covered
- [ ] Edge cases documented
- [ ] Error flows documented
- [ ] Setup instructions are clear

## Useful Commands
Commands to run related automated tests, if they exist.
```

## Step 3 — Map acceptance criteria

Each acceptance criterion from the User Story MUST have at least one corresponding test scenario in the QA_PLAN. Include a traceability table:

| Acceptance Criterion | Test Scenarios |
|---|---|
| [criterion 1] | TS-01, TS-03 |
| [criterion 2] | TS-02 |

## Step 4 — Verification

- Confirm all acceptance criteria are covered
- Verify steps are clear enough for someone unfamiliar with the project to execute
- Validate that prerequisites are complete

## Step 5 — Summary

Present:
- Number of scenarios created
- Acceptance criteria covered vs total
- Suggestions for automated tests to implement (if applicable)
