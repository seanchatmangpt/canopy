# Event Log Samples

This directory contains synthetic event logs for demonstrating OCPM discovery.

## Format

All event logs follow the OCPM standard format:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| case_id | string | Unique identifier for process instance | `INV-2024-001` |
| activity | string | Action performed | `approve_invoice` |
| timestamp | datetime | When activity occurred (ISO 8601) | `2024-03-23T12:00:00Z` |
| resource | string | Agent or system that performed activity | `accounting-bot` |
| amount | decimal | Transaction amount (invoice only) | `1500.00` |
| department | string | Business unit | `finance` |
| priority | string | Priority level | `high` |
| status | string | Activity result | `completed` |
| error_message | string | Error details (if failed) | `null` |

## Available Samples

### invoice_processing_events.csv (1000 cases, 415KB)
Invoice approval process with manual review bottlenecks.

**Process**: Receive → Validate → Review → Approve → Pay

**Bottlenecks**:
- Manual review: 45min p95 (appears in 80% of cases)
- Manager approval: 2hr p95 for high-value invoices

**Target**: 78% reduction in manual review time

---

### customer_onboarding_events.csv (800 cases, 377KB)
Customer onboarding with redundant touchpoints.

**Process**: Lead → Qualify → Configure → Setup → Train → Activate

**Bottlenecks**:
- Configuration: 2 business days (manual data entry)
- Setup: 1 business day (waiting for provisioning)

**Target**: 90% reduction in touch time

---

### compliance_reporting_events.csv (500 cases, 287KB)
Monthly compliance reporting with manual data collection.

**Process**: Collect → Validate → Aggregate → Report → File

**Bottlenecks**:
- Data collection: 6 hours (manual queries across systems)
- Validation: 1 hour (manual cross-checks)

**Target**: 100% automation

## Usage

Load event log for OCPM discovery:

```
canopy skills execute ocpm/discover_process \
  --event-log reference/event-log-samples/invoice_processing_events.csv \
  --output-format markdown
```

Or via skill call:

```json
{
  "event_log_source": "reference/event-log-samples/invoice_processing_events.csv",
  "output_format": "markdown",
  "include_bottlenecks": true,
  "include_deviations": true
}
```

## Data Quality

All synthetic event logs are:
- **Chronologically ordered** within cases
- **Complete** (no missing required fields)
- **Realistic** (based on actual process patterns)
- **Varied** (include edge cases, errors, exceptions)

## Generating New Samples

To generate additional synthetic event logs:

```python
python canopy/priv/demo_data/generate_event_log.py \
  --scenario invoice_processing \
  --cases 1000 \
  --output reference/event-log-samples/invoice_processing_events.csv
```
