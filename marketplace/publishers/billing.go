package publishers

import (
	"fmt"
	"time"
)

// ═══════════════════════════════════════════════════════════════════════════════
// BILLING & REVENUE — Stripe MPP integration and creator payouts
// ═══════════════════════════════════════════════════════════════════════════════

// BillingService manages payments and revenue sharing
type BillingService struct {
	stripeMPP *StripeMPPClient
	revenueStore RevenueStore
}

// StripeMPPClient handles Stripe Machine Payments Protocol integration
type StripeMPPClient struct {
	apiKey       string
	apiVersion   string
	publishableKey string
}

// RevenueStore tracks skill execution revenue
type RevenueStore interface {
	RecordExecution(skillID, workspaceID string, costUSD float64) error
	GetCreatorRevenue(creatorID, periodStart, periodEnd time.Time) (*CreatorRevenue, error)
	GetPlatformRevenue(periodStart, periodEnd time.Time) (*PlatformRevenue, error)
}

// UsageCharge represents a single skill execution charge
type UsageCharge struct {
	ChargeID      string    `json:"charge_id"`
	SkillID       string    `json:"skill_id"`
	WorkspaceID   string    `json:"workspace_id"`
	ExecutionID   string    `json:"execution_id"`
	PriceUSD      float64   `json:"price_usd"`
	Timestamp     time.Time `json:"timestamp"`
	Status        string    `json:"status"` // pending, completed, failed
}

// RevenueShare represents revenue distribution
type RevenueShare struct {
	SkillID        string    `json:"skill_id"`
	ExecutionID    string    `json:"execution_id"`
	GrossRevenue   float64   `json:"gross_revenue"`
	PlatformFee    float64   `json:"platform_fee"`    // 10%
	CreatorPayout  float64   `json:"creator_payout"`  // 90%
	PayoutStatus   string    `json:"payout_status"`   // pending, scheduled, completed
}

// CreatorRevenue tracks earnings for a creator
type CreatorRevenue struct {
	CreatorID        string           `json:"creator_id"`
	PeriodStart      time.Time        `json:"period_start"`
	PeriodEnd        time.Time        `json:"period_end"`
	Skills           []SkillRevenue   `json:"skills"`
	TotalCreatorUSD  float64          `json:"total_creator_usd"`
	PayoutStatus     string           `json:"payout_status"`
	PayoutDate       time.Time        `json:"payout_date"`
}

// SkillRevenue is revenue breakdown for a single skill
type SkillRevenue struct {
	SkillID         string  `json:"skill_id"`
	SkillName       string  `json:"skill_name"`
	Executions      int64   `json:"executions"`
	GrossRevenue    float64 `json:"gross_revenue"`
	PlatformFee     float64 `json:"platform_fee"`
	CreatorShare    float64 `json:"creator_share"`
}

// PlatformRevenue tracks total platform earnings
type PlatformRevenue struct {
	PeriodStart      time.Time `json:"period_start"`
	PeriodEnd        time.Time `json:"period_end"`
	TotalGMV         float64   `json:"total_gmv"`          // Gross Merchandise Value
	TotalPlatformFee float64   `json:"total_platform_fee"` // 10% of GMV
	TotalPayouts     float64   `json:"total_payouts"`      // 90% of GMV
	ActiveCreators   int       `json:"active_creators"`
	TotalExecutions  int64     `json:"total_executions"`
}

// BudgetEnforcement tracks workspace spending
type BudgetEnforcement struct {
	WorkspaceID      string    `json:"workspace_id"`
	MonthlyLimitUSD  float64   `json:"monthly_limit_usd"`
	ExecutionsThisMonth int64  `json:"executions_this_month"`
	CostThisMonth    float64   `json:"cost_this_month"`
	RemainingBudget  float64   `json:"remaining_budget"`
	RemainingExecutions int    `json:"remaining_executions"`
	ResetDate        time.Time `json:"reset_date"`
}

// NewBillingService creates a new billing service
func NewBillingService(apiKey string) *BillingService {
	return &BillingService{
		stripeMPP: &StripeMPPClient{
			apiKey:     apiKey,
			apiVersion: "2026-03-24",
		},
		// In production: inject actual RevenueStore implementation
	}
}

// ChargeExecution bills a workspace for skill execution
func (b *BillingService) ChargeExecution(skillID, workspaceID, executionID string, priceUSD float64) (*UsageCharge, error) {
	// 1. Check budget
	budget, err := b.checkBudget(workspaceID)
	if err != nil {
		return nil, fmt.Errorf("budget check failed: %w", err)
	}

	if budget.RemainingBudget < priceUSD {
		return nil, fmt.Errorf("insufficient budget: %.2f < %.2f", budget.RemainingBudget, priceUSD)
	}

	// 2. Create usage charge via Stripe MPP
	charge := &UsageCharge{
		ChargeID:    generateChargeID(),
		SkillID:     skillID,
		WorkspaceID: workspaceID,
		ExecutionID: executionID,
		PriceUSD:    priceUSD,
		Timestamp:   time.Now(),
		Status:      "pending",
	}

	// 3. Process charge
	if err := b.processCharge(charge); err != nil {
		return nil, fmt.Errorf("charge processing failed: %w", err)
	}

	// 4. Update budget
	budget.ExecutionsThisMonth++
	budget.CostThisMonth += priceUSD
	budget.RemainingBudget -= priceUSD

	// 5. Record revenue share
	revenueShare := b.calculateRevenueShare(charge)
	if err := b.recordRevenueShare(revenueShare); err != nil {
		return nil, fmt.Errorf("revenue recording failed: %w", err)
	}

	charge.Status = "completed"
	return charge, nil
}

// processCharge executes the Stripe MPP charge
func (b *BillingService) processCharge(charge *UsageCharge) error {
	// Stripe MPP API call
	// POST /v1/charges
	//
	// {
	//   "amount": charge.PriceUSD,
	//   "currency": "usd",
	//   "payment_method_types": ["usdc"],
	//   "confirm": true
	// }

	// In production: make actual Stripe API call
	// For now: simulate success
	return nil
}

// calculateRevenueShare splits revenue between platform and creator
func (b *BillingService) calculateRevenueShare(charge *UsageCharge) *RevenueShare {
	const (
		platformFeePercent = 0.10  // 10%
		creatorSharePercent = 0.90 // 90%
	)

	return &RevenueShare{
		SkillID:       charge.SkillID,
		ExecutionID:   charge.ExecutionID,
		GrossRevenue:  charge.PriceUSD,
		PlatformFee:   charge.PriceUSD * platformFeePercent,
		CreatorPayout: charge.PriceUSD * creatorSharePercent,
		PayoutStatus:  "pending",
	}
}

// recordRevenueShare stores revenue distribution
func (b *BillingService) recordRevenueShare(share *RevenueShare) error {
	// In production: store in database
	// For now: no-op
	return nil
}

// checkBudget validates workspace has sufficient budget
func (b *BillingService) checkBudget(workspaceID string) (*BudgetEnforcement, error) {
	// In production: fetch from database
	// For now: return default budget
	return &BudgetEnforcement{
		WorkspaceID:          workspaceID,
		MonthlyLimitUSD:      500.00,
		ExecutionsThisMonth:  0,
		CostThisMonth:        0,
		RemainingBudget:      500.00,
		RemainingExecutions:  10000,
		ResetDate:            nextMonthReset(),
	}, nil
}

// GetCreatorDashboard retrieves revenue analytics for a creator
func (b *BillingService) GetCreatorDashboard(creatorID string, month time.Time) (*CreatorRevenue, error) {
	periodStart := beginningOfMonth(month)
	periodEnd := endOfMonth(month)

	revenue, err := b.revenueStore.GetCreatorRevenue(creatorID, periodStart, periodEnd)
	if err != nil {
		return nil, err
	}

	return revenue, nil
}

// ProcessPayouts executes scheduled creator payouts
func (b *BillingService) ProcessPayouts(periodEnd time.Time) error {
	// 1. Get all creators with pending payouts
	// 2. For each creator:
	//    a. Calculate total payout
	//    b. Check minimum threshold ($10)
	//    c. Execute Stripe MPP payout
	//    d. Update payout status

	// In production: implement full payout pipeline
	return nil
}

// Helper functions
func generateChargeID() string {
	return fmt.Sprintf("charge_%d", time.Now().UnixNano())
}

func nextMonthReset() time.Time {
	now := time.Now()
	return time.Date(now.Year(), now.Month()+1, 1, 0, 0, 0, 0, time.UTC)
}

func beginningOfMonth(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, t.Location())
}

func endOfMonth(t time.Time) time.Time {
	return beginningOfMonth(t).AddDate(0, 1, 0).Add(-time.Second)
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKETPLACE STATS — Usage and revenue analytics
// ═══════════════════════════════════════════════════════════════════════════════

type MarketplaceStats struct {
	TotalSkills        int     `json:"total_skills"`
	LiveSkills         int     `json:"live_skills"`
	ActiveCreators     int     `json:"active_creators"`
	MonthlyExecutions  int64   `json:"monthly_executions"`
	MonthlyGMV         float64 `json:"monthly_gmv"`
	MonthlyPlatformRev float64 `json:"monthly_platform_rev"`
	MonthlyPayouts     float64 `json:"monthly_payouts"`
}

func (b *BillingService) GetMarketplaceStats(month time.Time) (*MarketplaceStats, error) {
	// In production: aggregate from database
	return &MarketplaceStats{
		TotalSkills:        50,
		LiveSkills:         42,
		ActiveCreators:     15,
		MonthlyExecutions:  125000,
		MonthlyGMV:         6250.00,
		MonthlyPlatformRev: 625.00,
		MonthlyPayouts:     5625.00,
	}, nil
}
