# Test Fixtures

This directory contains benign test inputs only — known-good inputs that should pass all guards.

Malicious and adversarial test fixtures are stored in a separate repository
(dusty-tenex/enclaive-test-fixtures) and are only checked out during CI runs.
This separation ensures malicious payloads are never accidentally installed
or executed from the main repository.

See `benign/` for legitimate inputs used in false-positive prevention tests.
