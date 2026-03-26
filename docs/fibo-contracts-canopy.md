# FIBO Contracts in Canopy

## Overview

Canopy's FIBO Contracts module provides deal management and contract templating for financial agreements. FIBO (Financial Industry Business Ontology) integration enables structured, standardized deal terms for multiple contract types including equity agreements, loan agreements, service agreements, and token-based instruments.

## Architecture

### Data Model

The deal lifecycle is managed through the `Canopy.Schemas.Deal` schema, which stores:

- **Deal Metadata**: Name, description, status, deal type
- **Financial Terms**: Amount (in cents), currency, counterparty
- **Contract References**: Template ID, embedded terms as JSON
- **Lifecycle Tracking**: Created by, assigned to, started at, completed at timestamps
- **Workspace Scope**: All deals belong to a workspace for multi-tenant isolation

#### Deal Status Flow

```
draft → negotiation → approved → signed → active → completed
                                    ↓
                               cancelled
```

- **draft**: Initial creation, not yet submitted
- **negotiation**: Under discussion with counterparty
- **approved**: Internal approval complete, ready to sign
- **signed**: Contract signed, `started_at` timestamp set
- **active**: Ongoing execution
- **completed**: Fulfillment complete, `completed_at` timestamp set
- **cancelled**: Deal terminated, can happen from any state

### Contract Templates

Contract templates are stored in `Canopy.Deals.ContractTemplate` as an in-memory catalog. Four template types are provided:

#### 1. Simple Agreement for Future Tokens (SAFT)

**Key:** `simple_agreement`

**Use Case:** Future token delivery agreements with investor and issuer

**Required Fields:**
- `issuer` (string): Token issuer entity name
- `investor` (string): Investor entity name
- `amount` (integer): Token quantity to be delivered
- `price_per_token` (float): Unit price in primary currency
- `delivery_date` (date, ISO8601): When tokens will be delivered

**Default Terms:**
- Governing Law: Delaware
- Dispute Resolution: Arbitration
- Payment Schedule: Net 30

**Example:**
```json
{
  "issuer": "AI Labs Inc",
  "investor": "Venture Partners LLP",
  "amount": 1000000,
  "price_per_token": 0.50,
  "delivery_date": "2027-06-30",
  "payment_terms": "Net 15"
}
```

#### 2. Equity Investment Agreement

**Key:** `equity_agreement`

**Use Case:** Equity investments with vesting and liquidation preferences

**Required Fields:**
- `company` (string): Company raising capital
- `investor` (string): Investor entity
- `investment_amount` (integer): Amount in cents (e.g., 1000000 = $10,000)
- `equity_percentage` (float): Equity stake (0-100)

**Optional Fields:**
- `vesting_period_months` (integer): Months until full vesting
- `liquidation_preference` (string): "none", "non-participating", "1x", "2x", etc.

**Default Terms:**
- Board Seat: false
- Pro Rata Rights: true
- Anti-Dilution: weighted_average
- Governing Law: Delaware

**Example:**
```json
{
  "company": "TechCo",
  "investor": "Seed Fund",
  "investment_amount": 500000,
  "equity_percentage": 5.0,
  "vesting_period_months": 48,
  "liquidation_preference": "1x"
}
```

#### 3. Loan Agreement

**Key:** `loan_agreement`

**Use Case:** Traditional loan with interest, repayment schedule, and collateral

**Required Fields:**
- `lender` (string): Lending entity
- `borrower` (string): Borrowing entity
- `principal_amount` (integer): Loan amount in cents
- `interest_rate_percent` (float): Annual interest rate (0-100)
- `term_months` (integer): Loan term in months

**Optional Fields:**
- `collateral_description` (string): Description of collateral securing loan

**Default Terms:**
- Payment Frequency: monthly
- Default Interest Rate: 3.0%
- Prepayment Penalty: false
- Governing Law: Delaware

**Example:**
```json
{
  "lender": "National Bank",
  "borrower": "Manufacturing Co",
  "principal_amount": 5000000,
  "interest_rate_percent": 4.5,
  "term_months": 60,
  "collateral_description": "Equipment and inventory"
}
```

#### 4. Service Agreement

**Key:** `service_agreement`

**Use Case:** Ongoing service delivery with SLAs and support terms

**Required Fields:**
- `service_provider` (string): Provider entity
- `client` (string): Client entity
- `monthly_fee` (integer): Recurring fee in cents
- `service_description` (string): What is being provided

**Optional Fields:**
- `sla_uptime_percent` (float): Target uptime percentage (0-100)
- `support_hours` (string): e.g., "24/7", "business hours", "9am-5pm EST"

**Default Terms:**
- Term: 12 months
- Auto-renewal: true
- Termination Notice: 30 days
- Governing Law: Delaware

**Example:**
```json
{
  "service_provider": "CloudOps LLC",
  "client": "Enterprise Inc",
  "monthly_fee": 50000,
  "service_description": "Managed cloud infrastructure and support",
  "sla_uptime_percent": 99.9,
  "support_hours": "24/7"
}
```

## API Endpoints

All endpoints require authentication and workspace scope.

### Deal Management

#### List Deals

```
GET /api/v1/deals?workspace_id={id}&status={status}&deal_type={type}
```

**Query Parameters:**
- `workspace_id` (required): Workspace UUID
- `status` (optional): Filter by deal status
- `deal_type` (optional): Filter by deal type

**Response:**
```json
{
  "deals": [
    {
      "id": "uuid",
      "name": "Series A Investment",
      "status": "active",
      "deal_type": "equity_agreement",
      "amount_cents": 1000000,
      "currency": "USD",
      "created_at": "2026-03-24T10:00:00Z",
      "started_at": "2026-04-01T14:30:00Z",
      "completed_at": null
    }
  ]
}
```

#### Create Deal

```
POST /api/v1/deals
```

**Body:**
```json
{
  "name": "Q2 2026 Financing",
  "deal_type": "loan_agreement",
  "description": "Operating capital loan",
  "amount_cents": 2000000,
  "currency": "USD",
  "counterparty": "Silicon Valley Bank",
  "workspace_id": "uuid",
  "created_by_id": "uuid"
}
```

**Response:** Deal object with 201 Created

#### Show Deal

```
GET /api/v1/deals/{id}
```

**Response:** Single deal object

#### Update Deal

```
PUT /api/v1/deals/{id}
```

**Body:** Partial update fields

**Supports:**
- Updating name, description, amount, counterparty
- Transitioning status via `"status": "new_status"`

#### Delete Deal

```
DELETE /api/v1/deals/{id}
```

**Constraint:** Only draft deals can be deleted

#### Sign Deal

```
POST /api/v1/deals/{id}/sign
```

**Effect:**
- Transitions status to `signed`
- Sets `started_at` to current timestamp
- Non-idempotent (calling twice sets timestamp twice)

#### Complete Deal

```
POST /api/v1/deals/{id}/complete
```

**Effect:**
- Transitions status to `completed`
- Sets `completed_at` to current timestamp

### Contract Templates

#### List Templates

```
GET /api/v1/deals/templates
```

**Response:**
```json
{
  "templates": [
    {
      "key": "simple_agreement",
      "name": "Simple Agreement for Future Tokens",
      "description": "Basic agreement for future token delivery"
    },
    {
      "key": "equity_agreement",
      "name": "Equity Investment Agreement",
      "description": "Agreement for equity investment with terms and conditions"
    }
  ]
}
```

#### Render Contract Template

```
POST /api/v1/deals/render-contract
```

**Body:**
```json
{
  "template_key": "simple_agreement",
  "terms": {
    "issuer": "TokenCo",
    "investor": "Investor LLC",
    "amount": 5000000,
    "price_per_token": 0.10,
    "delivery_date": "2027-12-31"
  }
}
```

**Response:**
```json
{
  "contract": {
    "name": "Simple Agreement for Future Tokens",
    "description": "Basic agreement for future token delivery",
    "terms": {
      "issuer": "TokenCo",
      "investor": "Investor LLC",
      "amount": 5000000,
      "price_per_token": 0.10,
      "delivery_date": "2027-12-31",
      "governing_law": "Delaware",
      "dispute_resolution": "Arbitration",
      "payment_schedule": "Net 30"
    },
    "metadata": {
      "template_key": null,
      "rendered_at": "2026-03-24T15:45:00Z",
      "version": "1.0"
    }
  }
}
```

**Validation:**
- Returns 422 if template not found
- Returns 422 if required fields missing or type incorrect
- Returns 422 if FIBO constraints violated (e.g., negative amounts, invalid currency)

#### Validate Contract Terms

```
POST /api/v1/deals/validate-contract
```

**Body:**
```json
{
  "template_key": "loan_agreement",
  "terms": {
    "lender": "Bank",
    "borrower": "Company",
    "principal_amount": 1000000,
    "interest_rate_percent": 5.5,
    "term_months": 60
  }
}
```

**Response (Valid):**
```json
{
  "valid": true
}
```

**Response (Invalid):**
```json
{
  "valid": false,
  "error": "Type mismatch for interest_rate_percent: expected float"
}
```

## Deal Lifecycle Example

### Scenario: Equity Investment Round

**Step 1: Create Draft Deal**

```bash
curl -X POST http://localhost:9089/api/v1/deals \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Series A Investment",
    "deal_type": "equity_agreement",
    "amount_cents": 5000000,
    "currency": "USD",
    "counterparty": "Seed Capital Fund",
    "workspace_id": "ws-uuid",
    "created_by_id": "user-uuid"
  }'
```

Response: Deal with status `draft`

**Step 2: Render Contract Template**

```bash
curl -X POST http://localhost:9089/api/v1/deals/render-contract \
  -H "Content-Type: application/json" \
  -d '{
    "template_key": "equity_agreement",
    "terms": {
      "company": "AI Labs",
      "investor": "Seed Capital Fund",
      "investment_amount": 5000000,
      "equity_percentage": 5.0,
      "vesting_period_months": 48
    }
  }'
```

Response: Full rendered contract with merged terms

**Step 3: Update Deal Terms**

```bash
curl -X PUT http://localhost:9089/api/v1/deals/{deal-id} \
  -H "Content-Type: application/json" \
  -d '{
    "status": "negotiation",
    "terms": {
      "company": "AI Labs",
      "investor": "Seed Capital Fund",
      "investment_amount": 5000000,
      "equity_percentage": 5.0,
      "vesting_period_months": 48,
      "board_seat": true
    }
  }'
```

**Step 4: Approve and Sign**

```bash
# Transition to approved
curl -X PUT http://localhost:9089/api/v1/deals/{deal-id} \
  -H "Content-Type: application/json" \
  -d '{"status": "approved"}'

# Sign the deal
curl -X POST http://localhost:9089/api/v1/deals/{deal-id}/sign
```

Response: Deal with status `signed` and `started_at` timestamp

**Step 5: Mark as Active and Complete**

```bash
# Start execution
curl -X PUT http://localhost:9089/api/v1/deals/{deal-id} \
  -H "Content-Type: application/json" \
  -d '{"status": "active"}'

# Mark complete
curl -X POST http://localhost:9089/api/v1/deals/{deal-id}/complete
```

Response: Deal with status `completed` and `completed_at` timestamp

## FIBO Constraints and Validation

The contract template module enforces financial instrument constraints:

### Amount Validation
- Must be positive integer (in cents)
- Zero amounts rejected
- Negative amounts rejected

### Interest Rate Validation
- Valid range: 0-100%
- Floating point or integer accepted
- Over 100% rejected

### Currency Validation
- Must be 3-letter ISO 4217 code
- Examples: USD, EUR, GBP, JPY, CNY
- Invalid formats rejected

### Type Validation

Field types supported:
- `:string` - Text values
- `:integer` - Whole numbers (cents, months)
- `:float` - Decimal numbers (rates, percentages)
- `:date` - ISO8601 date strings
- `:boolean` - true/false
- `:map` - JSON objects

### Required vs Optional

Each template field marked as:
- `required: true` - Must be present in terms
- `required: false` - Optional, can be omitted

Missing required fields trigger validation errors:
```json
{
  "error": "Validation failed: Required field missing: issuer"
}
```

## Integration with OSA

Deals can integrate with OSA via the agent system for:

- **Deal Monitoring**: Agents track deal lifecycle and alert on milestones
- **Compliance Checks**: OSA compliance agent validates contracts against SOC2/HIPAA rules
- **Document Generation**: OSA agent generates contract PDFs and signatures
- **Workflow Automation**: OSA coordinates document routing and approvals

### Example: Compliance Check Agent Task

```elixir
{:ok, agent} = Canopy.get_agent("compliance-check")

deal_id = "deal-uuid"
{:ok, deal} = Canopy.Repo.get(Deal, deal_id)

task = %{
  "type" => "validate_compliance",
  "deal_id" => deal_id,
  "contract_type" => deal.deal_type,
  "terms" => deal.terms
}

# Agent receives task, checks FIBO and SOC2 compliance
Canopy.dispatch(agent, task)
```

## View Helpers

The `CanopyWeb.DealsView` module provides helpers for rendering in web interfaces:

```elixir
# Format cents as currency
CanopyWeb.DealsView.format_amount(500000)  # "5000.00"

# Get status label
CanopyWeb.DealsView.status_label("signed")  # "Signed"

# Get CSS badge class
CanopyWeb.DealsView.status_badge_class("completed")  # "badge-success"

# Get deal timeline
CanopyWeb.DealsView.deal_timeline(deal)  # [{event, timestamp}, ...]
```

## Error Handling

### Common Errors

**404 Not Found**
```json
{"error": "not_found"}
```
Deal or template does not exist

**422 Validation Failed**
```json
{
  "error": "validation_failed",
  "details": {
    "name": ["can't be blank"],
    "amount_cents": ["must be greater than or equal to 0"]
  }
}
```
Invalid deal data or constraint violation

**422 Cannot Delete Non-Draft**
```json
{
  "error": "cannot_delete_non_draft",
  "message": "Only draft deals can be deleted"
}
```
Attempted to delete deal with status other than draft

**422 Type Mismatch**
```json
{
  "error": "Type mismatch for interest_rate_percent: expected float"
}
```
Contract term has wrong type for field

## Testing

All endpoints and contract templates are tested via:

1. **Unit Tests** (`test/canopy/deals/contract_template_test.exs`)
   - Template loading and validation
   - Field type checking
   - FIBO constraint validation
   - Contract rendering

2. **Controller Tests** (`test/canopy_web/controllers/deals_controller_test.exs`)
   - CRUD operations on deals
   - Status transitions
   - Template rendering via API
   - Contract validation via API

Run tests:
```bash
cd canopy/backend
mix test test/canopy/deals/
mix test test/canopy_web/controllers/deals_controller_test.exs
```

## Future Extensions

### Planned Features

1. **Digital Signatures**: Integration with e-signature providers (Docusign, HelloSign)
2. **Contract Storage**: Store rendered contracts as files/PDFs
3. **Audit Trail**: Complete versioning and change tracking
4. **Custom Templates**: Allow users to define custom contract templates
5. **Multi-Currency**: Support currency conversion and FX rates
6. **Regulatory Compliance**: GDPR, SOX, HIPAA-specific clauses
7. **Deal Analytics**: Revenue recognition, payment tracking, KPIs

### Extension Points

- Add new template keys to `ContractTemplate.templates()`
- Implement `Canopy.Contracts.DigitalSignature` for e-signature integration
- Create `CanopyWeb.ContractExportController` for PDF/document export
- Build `Canopy.Deals.AuditLog` for change tracking

## References

- **FIBO (Financial Industry Business Ontology)**: https://spec.edmcouncil.org/fibo/
- **Ecto Schemas**: https://hexdocs.pm/ecto/Ecto.Schema.html
- **Phoenix Controllers**: https://hexdocs.pm/phoenix/Phoenix.Controller.html
- **Elixir Type System**: https://elixir-lang.org/getting-started/basic-types.html
