# Engineering Guidelines

## Core Principles

- Prioritize correctness, clarity, maintainability and security over "just making it work".
- Prefer the simplest solution that satisfies the requirements without sacrificing engineering quality.
- Avoid both under-engineering and unnecessary over-engineering.
- Use established architectural and design patterns where they provide a clear benefit.
- Prefer standards and established solutions over custom implementations.

## Code Quality

- Keep code and files consistently well-formatted, indented and easy to read.
- Use clear, explicit and descriptive names for classes, methods, variables and files.
- Maintain strong separation of responsibilities and minimize unnecessary coupling.
- Prefer cohesive modules with explicit dependencies.
- Avoid duplicated logic.
- Prefer abstractions when they improve maintainability or express a meaningful domain concept.
- Do not introduce abstractions without a clear purpose.

## Configuration

- Prefer configuration through environment variables, configuration files or constants.
- Do not scatter configuration values or literals throughout the codebase.
- Keep configurable values centralized and clearly named.
- Never commit secrets or credentials to Git.

## Architecture

- Analyze the existing architecture before implementing significant changes.
- Do not introduce architectural changes without explaining the motivation.
- When multiple valid solutions exist, explain the main alternatives and trade-offs before choosing.
- Do not introduce technologies, libraries or infrastructure components without a concrete need.
- Prefer framework-native and standard solutions over custom mechanisms.
- Do not modify or circumvent framework behavior to force a solution to work.
- Investigate the root cause and use the framework as intended.
- Avoid introducing dependencies between components unless they are justified.

## Security

- Treat security as part of the design, not as a later step.
- Prefer established security standards and best practices.
- For security decisions, prefer authoritative sources such as IETF/RFCs, OWASP, NIST and official technology documentation.
- Never implement custom authentication or cryptographic mechanisms when standard solutions exist.
- Never expose or commit secrets, credentials or sensitive configuration.

## Testing

- Testing is mandatory, not optional.
- Define the testing strategy before or alongside implementation.
- Choose the appropriate test level: unit, integration, component, contract or end-to-end.
- Every significant feature or behavior change must include appropriate tests.
- Run relevant tests and validation after significant changes.
- Never hide or bypass failing tests, warnings or errors just to obtain a passing build.
- Investigate failures and fix their root cause.

## Documentation

- Keep documentation concise, structured and optimized for fast human and AI consumption.
- Avoid unnecessary prose, repetition and duplication.
- Document significant architectural decisions, not implementation details that are already evident from the code.
- Use ADRs for important architectural decisions.
- ADRs should contain: context, decision, alternatives and consequences.
- Keep documentation synchronized with the implementation.

## Educational Workflow

The project is also a learning environment.

For every significant architectural, technological or engineering decision, briefly explain:

1. **What** is being introduced.
2. **Why** it is needed.
3. **How** it works.
4. **Which pattern or principle** is being applied.
5. **Main trade-offs**.

Keep explanations concise and concrete. Do not turn explanations into long tutorials unless explicitly requested.

## Change Management

- Make changes focused and minimal.
- Do not modify unrelated code or perform opportunistic refactoring.
- Before significant changes, inspect the relevant existing code and configuration.
- After implementation, summarize what changed and how it was verified.
- Do not assume unstated requirements.
- Ask for clarification when an architectural decision materially depends on missing requirements.

## Git

- Use Conventional Commits.
- Commit format:

  `type(scope): description`

- Prefer small, focused commits.
- Do not mix unrelated changes in the same commit.
- Commit messages must clearly describe the change.

## File Organization

- Keep project structure predictable and easy to navigate.
- Group files by responsibility and domain.
- Avoid unnecessary nesting.
- Keep related configuration close together.
- Optimize all generated files, including this document, for clarity and low token consumption.