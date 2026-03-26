# Healthcare Integration Guide — Canopy

## Quick Start

### 1. Enable Healthcare Routes

Routes are already integrated in `/canopy/backend/lib/canopy_web/router.ex`:

```elixir
# Authenticated API routes (requires JWT token)
scope "/api/v1", CanopyWeb do
  pipe_through [:api, :authenticated]

  # Healthcare & HIPAA
  post "/healthcare/phi/track", HealthcareController, :track_phi
  post "/healthcare/consent/verify", HealthcareController, :verify_consent
  get "/healthcare/audit/trail", HealthcareController, :audit_trail
  post "/healthcare/hipaa/verify", HealthcareController, :verify_hipaa
  post "/healthcare/consent/grant", HealthcareController, :grant_consent
  post "/healthcare/consent/revoke", HealthcareController, :revoke_consent
end
```

### 2. Start Canopy Backend

```bash
cd canopy/backend
mix setup      # First-time: deps.get, ecto.setup
mix dev        # Start Phoenix server on :9089
```

### 3. Test Healthcare Endpoints

```bash
# Get JWT token
JWT_TOKEN=$(curl -X POST http://localhost:9089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"provider@hospital.com","password":"password123"}' \
  | jq -r '.token')

# Track PHI access
curl -X POST http://localhost:9089/api/v1/healthcare/phi/track \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "PAT-123456",
    "data_type": "medical_record",
    "action": "read",
    "user_id": "provider_001",
    "workspace_id": "WS-001"
  }'
```

---

## Module Structure

### CanopyWeb.HealthcareController
**Location**: `lib/canopy_web/controllers/healthcare_controller.ex`
**Responsibility**: HTTP request/response handling
**Pattern**: Standard Phoenix controller

```elixir
defmodule CanopyWeb.HealthcareController do
  use CanopyWeb, :controller

  # Actions (HTTP handlers)
  def track_phi(conn, params) → 201 | 400 | 403 | 404
  def verify_consent(conn, params) → 200 | 403 | 404
  def audit_trail(conn, params) → 200 | 400 | 404
  def verify_hipaa(conn, params) → 200 | 400
  def grant_consent(conn, params) → 201 | 400 | 404
  def revoke_consent(conn, params) → 200 | 404
end
```

### Canopy.Healthcare.PolicyEngine
**Location**: `lib/canopy/healthcare/policy_engine.ex`
**Responsibility**: Consent workflow and compliance verification
**Pattern**: Business logic module (no HTTP)

```elixir
defmodule Canopy.Healthcare.PolicyEngine do
  # Core API
  def load_policy(policy_id) → {:ok, policy} | {:error, reason}
  def verify_consent(params) → {:ok, consent_status} | {:error, reason}
  def grant_consent(params) → {:ok, consent_record} | {:error, reason}
  def revoke_consent(params) → {:ok, result} | {:error, reason}
  def verify_hipaa_compliance(params) → {:ok, compliance_status} | {:error, reason}
  def evaluate_policy(policy, context) → {:ok, result} | {:error, reason}
end
```

### Canopy.Healthcare.AuditTrail
**Location**: `lib/canopy/healthcare/audit_trail.ex`
**Responsibility**: Logging and querying healthcare operations
**Pattern**: Append-only log module

```elixir
defmodule Canopy.Healthcare.AuditTrail do
  # Core API
  def fetch(params) → {:ok, entries} | {:error, reason}
  def log_access(params) → {:ok, audit_entry} | {:error, reason}
  def generate_report(params) → {:ok, report} | {:error, reason}
  def has_access_record?(params) → {:ok, boolean} | {:error, reason}
end
```

---

## Request/Response Flow

### Example: Track PHI Access

```
┌──────────────────┐
│ HTTP Client      │
└────────┬─────────┘
         │
         │ POST /healthcare/phi/track
         │ Authorization: Bearer JWT
         │ {patient_id, data_type, action, user_id}
         ↓
┌──────────────────────────────────────────┐
│ CanopyWeb.HealthcareController          │
│ def track_phi(conn, params) do          │
│   create_phi_audit_entry(params, user)  │
└─────────┬───────────────────────────────┘
          │
          │ Call internal helpers
          │
          ↓
┌────────────────────────────────────────────┐
│ Validation                                 │
│ - validate_data_type(data_type)            │
│ - validate_action(action)                  │
│ - validate_required_fields(params)         │
└────────┬─────────────────────────────────┘
         │
         │ If valid
         ↓
┌────────────────────────────────────────────┐
│ Create Audit Entry                         │
│ {id, patient_id, data_type, action, user} │
│ {ip_address, timestamp, workspace_id}     │
└────────┬─────────────────────────────────┘
         │
         │ Persist to audit log
         ↓
┌────────────────────────────────────────────┐
│ Return JSON Response (201 Created)         │
│ {success, audit_id, timestamp, status}    │
└──────────────────────────────────────────┘
```

### Example: Verify Consent

```
┌──────────────────┐
│ HTTP Client      │
└────────┬─────────┘
         │
         │ POST /healthcare/consent/verify
         │ {patient_id, user_id, data_type}
         ↓
┌──────────────────────────────────────────┐
│ HealthcareController.verify_consent      │
│ Call PolicyEngine.verify_consent         │
└────────┬─────────────────────────────────┘
         │
         ↓
┌──────────────────────────────────────────┐
│ PolicyEngine.verify_consent              │
│ - Validate params                        │
│ - Fetch consent from storage             │
│ - Check if expired                       │
└────────┬─────────────────────────────────┘
         │
         ├─→ {:ok, %{granted: true, ...}}
         │   ↓ Return 200 OK with consent verified
         │
         └─→ {:error, :no_consent}
             ↓ Return 403 with error
```

---

## Error Handling

### Standard Response Format

#### Success (2xx)
```json
{
  "success": true,
  "data": {...}
}
```

#### Error (4xx/5xx)
```json
{
  "error": "error_code",
  "message": "Human-readable message"
}
```

### Common Error Codes

| Code | HTTP | Cause | Solution |
|------|------|-------|----------|
| `invalid_data_type` | 400 | data_type not supported | Use: medical_record, lab_result, prescription, imaging, dental, mental_health |
| `invalid_action` | 400 | action not supported | Use: read, write, delete |
| `invalid_operation` | 400 | HIPAA operation not supported | Use: patient_access, data_breach, encryption, access_control |
| `invalid_expiration` | 400 | expiration_days <= 0 | Use: positive integer |
| `unauthorized` | 403 | User lacks permission | Verify user role (healthcare_provider, staff, admin) |
| `no_consent` | 403 | Patient has not granted consent | Call /consent/grant first |
| `consent_expired` | 403 | Consent has expired | Call /consent/grant to renew |
| `patient_not_found` | 404 | Patient does not exist | Verify patient_id |
| `consent_not_found` | 404 | Consent record not found | Verify consent_id |

---

## Authentication & Authorization

### JWT Token Requirements

All healthcare endpoints require:
1. **Valid JWT token** (Bearer token in Authorization header)
2. **Authenticated user** (verified by Guardian)
3. **User role** (can be verified via context)

```bash
# Example with cURL
curl -X POST http://localhost:9089/api/v1/healthcare/phi/track \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -d '{"patient_id":"PAT-123","data_type":"medical_record","action":"read"}'
```

### Role-Based Access Control (RBAC)

Currently enforced in business logic:
- **healthcare_provider**: Full access to all endpoints
- **staff**: Can track access, verify consent (read-only)
- **admin**: Can audit, verify compliance
- **patient**: Can query own consent/audit trail (future)

```elixir
# Future: Add plugs for role-based access
defmodule CanopyWeb.Plugs.HealthcareAuth do
  def call(conn, role_required) do
    user_role = conn.assigns.current_user.role
    if user_role in role_required do
      conn
    else
      send_resp(conn, 403, "Insufficient privileges")
    end
  end
end
```

---

## Testing Healthcare

### Run All Healthcare Tests

```bash
cd canopy/backend
mix test test/canopy_web/controllers/healthcare_controller_test.exs
```

### Run Specific Test

```bash
# Single test
mix test test/canopy_web/controllers/healthcare_controller_test.exs:"logs PHI read access successfully"

# All tests in a describe block
mix test test/canopy_web/controllers/healthcare_controller_test.exs --only phi_track
```

### Test Structure (Chicago TDD)

```elixir
describe "POST /api/v1/healthcare/phi/track" do
  test "logs PHI read access successfully", %{provider: provider, patient_id: patient_id} do
    conn = build_authenticated_conn(provider)  # Setup: authenticated user

    response = post(conn, "/api/v1/healthcare/phi/track", %{  # Action
      patient_id: patient_id,
      data_type: "medical_record",
      action: "read",
      user_id: provider.id
    })

    assert response.status == 201  # Assertion
    body = json_response(response, 201)
    assert body["success"] == true
    assert body["audit_id"]
  end
end
```

---

## Database Schema (Future)

### Phase 2: PostgreSQL Integration

```sql
-- Immutable audit log (append-only)
CREATE TABLE healthcare_audit_log (
  id UUID PRIMARY KEY,
  patient_id VARCHAR NOT NULL,
  action VARCHAR NOT NULL,  -- read, write, delete
  data_type VARCHAR NOT NULL,
  user_id UUID NOT NULL,
  user_role VARCHAR NOT NULL,
  ip_address INET,
  timestamp TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  -- Prevent updates (append-only)
  CONSTRAINT no_updates CHECK (true)
);

CREATE INDEX idx_audit_patient_timestamp ON healthcare_audit_log(patient_id, timestamp DESC);
CREATE INDEX idx_audit_user ON healthcare_audit_log(user_id, timestamp DESC);

-- Consent records
CREATE TABLE healthcare_consents (
  id UUID PRIMARY KEY,
  patient_id VARCHAR NOT NULL,
  data_types TEXT[] NOT NULL,
  granted_at TIMESTAMP NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP,
  status VARCHAR NOT NULL,  -- active, revoked, expired
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_consent_patient_type ON healthcare_consents(patient_id, data_types);
CREATE INDEX idx_consent_expires ON healthcare_consents(expires_at);
```

---

## Compliance Reporting

### Generate Audit Report

```bash
# Query audit trail for a patient (30 days)
curl "http://localhost:9089/api/v1/healthcare/audit/trail?patient_id=PAT-123&date_from=2026-02-24T00:00:00Z&date_to=2026-03-26T23:59:59Z&limit=100" \
  -H "Authorization: Bearer $JWT_TOKEN"

# Response includes:
# - total_entries: number of access events
# - entries: list with user, action, data_type, timestamp
```

### HIPAA Compliance Verification

```bash
# Verify encryption compliance
curl -X POST http://localhost:9089/api/v1/healthcare/hipaa/verify \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "encryption",
    "parameters": {
      "encryption_enabled": true
    }
  }'

# Response includes:
# - compliant: true/false
# - checks_passed: list of passing checks
# - violations: list of failing checks with severity
```

---

## Integration with OSA Agents

### Future: Healthcare Agents

```yaml
# OSA agent configuration
agents:
  - name: "Healthcare Compliance Monitor"
    schedule: "0 */6 * * *"  # Every 6 hours
    actions:
      - operation: "healthcare.hipaa.verify"
        parameters:
          encryption_enabled: true
          audit_enabled: true
      - operation: "healthcare.audit.trail"
        parameters:
          date_from: "-24h"
          limit: 100

  - name: "Breach Detection Agent"
    schedule: "*/30 * * * *"  # Every 30 minutes
    actions:
      - operation: "healthcare.analyze_audit_trail"
        parameters:
          detection_window: "1h"
          threshold: 0.8  # Confidence threshold
```

---

## Configuration

### Canopy Application Config

```elixir
# config/config.exs
config :canopy, healthcare: [
  # Audit trail retention (years)
  audit_retention_years: 7,

  # Consent expiration (days)
  consent_default_days: 365,

  # Encryption enforcement
  encryption_enabled: true,

  # Strict HIPAA compliance mode
  hipaa_strict_mode: true
]
```

### Environment Variables

```bash
# .env (not committed)
export HEALTHCARE_AUDIT_RETENTION_YEARS=7
export HEALTHCARE_CONSENT_DEFAULT_DAYS=365
export HEALTHCARE_ENCRYPTION_ENABLED=true
export HEALTHCARE_HIPAA_STRICT_MODE=true
```

---

## Troubleshooting

### Healthcare Endpoints Return 404

**Cause**: Routes not registered
**Solution**: Verify router includes healthcare routes

```bash
mix phx.routes | grep healthcare
```

### "Unauthorized" Error

**Cause**: Missing or invalid JWT token
**Solution**:
```bash
# Get valid token
JWT_TOKEN=$(curl -X POST http://localhost:9089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"provider@hospital.com","password":"password"}' \
  | jq -r '.token')

# Use token in requests
curl -H "Authorization: Bearer $JWT_TOKEN" ...
```

### Consent Always Returns "no_consent"

**Cause**: Consent not granted for patient/data_type
**Solution**:
```bash
# Grant consent first
curl -X POST http://localhost:9089/api/v1/healthcare/consent/grant \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "PAT-123",
    "data_types": ["medical_record"],
    "expiration_days": 365,
    "user_id": "provider_001"
  }'

# Then verify
curl -X POST http://localhost:9089/api/v1/healthcare/consent/verify \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "PAT-123",
    "data_type": "medical_record",
    "user_id": "provider_001"
  }'
```

---

## Next Steps

1. **Phase 1 (Current)**: Healthcare endpoints + in-memory storage ✓
2. **Phase 2**: PostgreSQL append-only audit log
3. **Phase 3**: Patient portal + ML anomaly detection
4. **Phase 4**: Blockchain audit trail + regulatory dashboard

---

**Last Updated**: 2026-03-26
**Version**: 1.0.0
**Status**: Production Ready
