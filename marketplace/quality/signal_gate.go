package quality

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// ═══════════════════════════════════════════════════════════════════════════════
// QUALITY GATE — Signal Theory S/N scoring for skill approval
// ═══════════════════════════════════════════════════════════════════════════════

// QualityGate evaluates skills for marketplace approval
type QualityGate struct {
	minSNRatio float64
	securityScanner *SecurityScanner
	testValidator   *TestValidator
}

// QualityScore represents the S/N quality assessment
type QualityScore struct {
	SNRatio    float64    `json:"s_n_ratio"`    // 0.0 to 1.0
	Rank       string     `json:"rank"`         // optimal, good, pass, fail
	Factors    Factors    `json:"factors"`
	LastCheck  time.Time  `json:"last_check"`
	Reason     []string   `json:"reason"`       // Approval/rejection reasons
}

// Factors are the individual quality components
type Factors struct {
	Documentation   float64 `json:"documentation"`   // Completeness of docs
	SignalEncoding  float64 `json:"signal_encoding"`  // S=(M,G,T,F,W) defined
	Tests           float64 `json:"tests"`           // Test coverage
	Security        float64 `json:"security"`        // Malicious patterns
	ErrorHandling   float64 `json:"error_handling"`   // Error cases covered
	Efficiency      float64 `json:"efficiency"`      // Resource usage
}

// NewQualityGate creates a new quality gate
func NewQualityGate() *QualityGate {
	return &QualityGate{
		minSNRatio:      0.7,
		securityScanner: NewSecurityScanner(),
		testValidator:   NewTestValidator(),
	}
}

// Evaluate scores a skill for marketplace approval
func (q *QualityGate) Evaluate(content string, metadata map[string]interface{}) (QualityScore, error) {
	score := QualityScore{
		LastCheck: time.Now(),
		Reason:    make([]string, 0),
	}

	// Extract metadata
	metadataStr := fmt.Sprintf("%v", metadata)

	// Factor 1: Documentation completeness
	score.Factors.Documentation = q.evaluateDocumentation(content, metadataStr)
	score.Reason = append(score.Reason, fmt.Sprintf("Documentation: %.2f", score.Factors.Documentation))

	// Factor 2: Signal Theory encoding
	score.Factors.SignalEncoding = q.evaluateSignalEncoding(metadata)
	score.Reason = append(score.Reason, fmt.Sprintf("Signal encoding: %.2f", score.Factors.SignalEncoding))

	// Factor 3: Security check
	securityResult := q.securityScanner.Scan(content)
	score.Factors.Security = securityResult.Score
	if securityResult.HasMaliciousPatterns {
		score.Reason = append(score.Reason, "SECURITY: Malicious patterns detected")
	}
	score.Reason = append(score.Reason, fmt.Sprintf("Security: %.2f", score.Factors.Security))

	// Factor 4: Test coverage
	score.Factors.Tests = q.testValidator.Validate(content)
	score.Reason = append(score.Reason, fmt.Sprintf("Tests: %.2f", score.Factors.Tests))

	// Factor 5: Error handling
	score.Factors.ErrorHandling = q.evaluateErrorHandling(content)
	score.Reason = append(score.Reason, fmt.Sprintf("Error handling: %.2f", score.Factors.ErrorHandling))

	// Factor 6: Efficiency
	score.Factors.Efficiency = q.evaluateEfficiency(content)
	score.Reason = append(score.Reason, fmt.Sprintf("Efficiency: %.2f", score.Factors.Efficiency))

	// Calculate overall S/N ratio (weighted average)
	score.SNRatio = q.calculateSNRatio(score.Factors)

	// Determine rank
	score.Rank = q.determineRank(score.SNRatio)

	// Add approval decision
	if score.SNRatio >= q.minSNRatio {
		score.Reason = append(score.Reason, fmt.Sprintf("✅ APPROVED: S/N %.2f ≥ %.2f", score.SNRatio, q.minSNRatio))
	} else {
		score.Reason = append(score.Reason, fmt.Sprintf("❌ REJECTED: S/N %.2f < %.2f", score.SNRatio, q.minSNRatio))
	}

	return score, nil
}

// evaluateDocumentation checks for complete documentation
func (q *QualityGate) evaluateDocumentation(content, metadata string) float64 {
	score := 0.0
	maxScore := 5.0
	weight := maxScore / 5.0

	// Check for description
	if strings.Contains(content, "# ") || strings.Contains(content, "## ") {
		score += weight
	}

	// Check for purpose
	if strings.Contains(strings.ToLower(content), "purpose") {
		score += weight
	}

	// Check for input/output examples
	if strings.Contains(content, "Input:") || strings.Contains(content, "Output:") {
		score += weight
	}

	// Check for usage instructions
	if strings.Contains(strings.ToLower(content), "usage") || strings.Contains(strings.ToLower(content), "example") {
		score += weight
	}

	// Check for tools section
	if strings.Contains(content, "tools:") || strings.Contains(content, "tools_required") {
		score += weight
	}

	return score / maxScore
}

// evaluateSignalEncoding checks for S=(M,G,T,F,W) encoding
func (q *QualityGate) evaluateSignalEncoding(metadata map[string]interface{}) float64 {
	score := 0.0
	maxScore := 5.0
	weight := maxScore / 5.0

	metadataStr := fmt.Sprintf("%v", metadata)
	metadataLower := strings.ToLower(metadataStr)

	// Mode (M)
	if strings.Contains(metadataLower, "mode") || strings.Contains(metadataLower, "linguistic") || strings.Contains(metadataLower, "visual") {
		score += weight
	}

	// Genre (G)
	if strings.Contains(metadataLower, "genre") || strings.Contains(metadataLower, "inform") || strings.Contains(metadataLower, "direct") {
		score += weight
	}

	// Type (T)
	if strings.Contains(metadataLower, "type") || strings.Contains(metadataLower, "direct") || strings.Contains(metadataLower, "commit") {
		score += weight
	}

	// Format (F)
	if strings.Contains(metadataLower, "format") || strings.Contains(metadataLower, "markdown") || strings.Contains(metadataLower, "json") {
		score += weight
	}

	// Structure (W)
	if strings.Contains(metadataLower, "structure") || strings.Contains(metadataLower, "template") {
		score += weight
	}

	return score / maxScore
}

// evaluateErrorHandling checks for error handling coverage
func (q *QualityGate) evaluateErrorHandling(content float64) float64 {
	contentLower := strings.ToLower(content)
	score := 0.0
	maxScore := 4.0
	weight := maxScore / 4.0

	// Error handling mentions
	if strings.Contains(contentLower, "error") || strings.Contains(contentLower, "fail") {
		score += weight
	}

	// Retry logic
	if strings.Contains(contentLower, "retry") || strings.Contains(contentLower, "attempt") {
		score += weight
	}

	// Validation
	if strings.Contains(contentLower, "validate") || strings.Contains(contentLower, "check") {
		score += weight
	}

	// Fallback behavior
	if strings.Contains(contentLower, "fallback") || strings.Contains(contentLower, "default") {
		score += weight
	}

	return score / maxScore
}

// evaluateEfficiency checks for efficiency considerations
func (q *QualityGate) evaluateEfficiency(content float64) float64 {
	contentLower := strings.ToLower(content)
	score := 0.0
	maxScore := 3.0
	weight := maxScore / 3.0

	// Caching mentioned
	if strings.Contains(contentLower, "cache") {
		score += weight
	}

	// Batch operations
	if strings.Contains(contentLower, "batch") {
		score += weight
	}

	// Async/parallel
	if strings.Contains(contentLower, "async") || strings.Contains(contentLower, "parallel") {
		score += weight
	}

	return score / maxScore
}

// calculateSNRatio computes weighted average of factors
func (q *QualityGate) calculateSNRatio(f Factors) float64 {
	weights := map[string]float64{
		"documentation":  0.20,
		"signal_encoding": 0.25,
		"tests":          0.20,
		"security":       0.20,
		"error_handling": 0.10,
		"efficiency":     0.05,
	}

	total := 0.0
	total += f.Documentation * weights["documentation"]
	total += f.SignalEncoding * weights["signal_encoding"]
	total += f.Tests * weights["tests"]
	total += f.Security * weights["security"]
	total += f.ErrorHandling * weights["error_handling"]
	total += f.Efficiency * weights["efficiency"]

	return total
}

// determineRank converts S/N ratio to rank
func (q *QualityGate) determineRank(snRatio float64) string {
	if snRatio >= 0.9 {
		return "optimal"
	}
	if snRatio >= 0.7 {
		return "good"
	}
	if snRatio >= 0.5 {
		return "pass"
	}
	return "fail"
}

// IsApproved checks if score meets approval threshold
func (q *QualityGate) IsApproved(score QualityScore) bool {
	return score.SNRatio >= q.minSNRatio
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECURITY SCANNER — Malicious pattern detection
// ═══════════════════════════════════════════════════════════════════════════════

type SecurityScanner struct {
	maliciousPatterns []*regexp.Regexp
}

type SecurityScanResult struct {
	Score                 float64 `json:"score"`
	HasMaliciousPatterns  bool    `json:"has_malicious_patterns"`
	DetectedPatterns      []string `json:"detected_patterns"`
}

func NewSecurityScanner() *SecurityScanner {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)password\s*=\s*["\'][^"\']+["\']`),           // Hardcoded passwords
		regexp.MustCompile(`(?i)api[_-]?key\s*=\s*["\'][^"\']+["\']`),            // Hardcoded API keys
		regexp.MustCompile(`(?i)secret\s*=\s*["\'][^"\']+["\']`),                 // Hardcoded secrets
		regexp.MustCompile(`(?i)token\s*=\s*["\'][^"\']+["\']`),                  // Hardcoded tokens
		regexp.MustCompile(`(?i)eval\s*\(`),                                       // Dangerous eval
		regexp.MustCompile(`(?i)exec\s*\(`),                                       // Dangerous exec
		regexp.MustCompile(`(?i)system\s*\(`),                                     // Dangerous system calls
		regexp.MustCompile(`(?i)shell\s*=\s*true`),                                // Shell execution flags
		regexp.MustCompile(`(?i)rm\s+-rf`),                                        // Dangerous file operations
		regexp.MustCompile(`(?i)DROP\s+TABLE`),                                    // SQL injection patterns
		regexp.MustCompile(`(?i)<script`),                                         // XSS patterns
	}

	return &SecurityScanner{
		maliciousPatterns: patterns,
	}
}

func (s *SecurityScanner) Scan(content string) SecurityScanResult {
	result := SecurityScanResult{
		Score:            1.0,
		DetectedPatterns: make([]string, 0),
	}

	contentLower := strings.ToLower(content)

	for _, pattern := range s.maliciousPatterns {
		if pattern.MatchString(contentLower) {
			result.HasMaliciousPatterns = true
			result.DetectedPatterns = append(result.DetectedPatterns, pattern.String())
			result.Score -= 0.5
		}
	}

	if result.Score < 0 {
		result.Score = 0
	}

	return result
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEST VALIDATOR — Check for test coverage
// ═══════════════════════════════════════════════════════════════════════════════

type TestValidator struct{}

func NewTestValidator() *TestValidator {
	return &TestValidator{}
}

func (t *TestValidator) Validate(content string) float64 {
	contentLower := strings.ToLower(content)
	score := 0.0
	maxScore := 4.0
	weight := maxScore / 4.0

	// Test file mentioned
	if strings.Contains(contentLower, "test") || strings.Contains(contentLower, "spec") {
		score += weight
	}

	// Test examples
	if strings.Contains(contentLower, "example") || strings.Contains(contentLower, "sample") {
		score += weight
	}

	// Expected output
	if strings.Contains(contentLower, "expected") || strings.Contains(contentLower, "should") {
		score += weight
	}

	// Edge cases mentioned
	if strings.Contains(contentLower, "edge case") || strings.Contains(contentLower, "error case") {
		score += weight
	}

	return score / maxScore
}
