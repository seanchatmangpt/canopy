package registry

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"time"
)

// ═══════════════════════════════════════════════════════════════════════════════
// SKILL REGISTRY — Published skill metadata and versioning
// ═══════════════════════════════════════════════════════════════════════════════

// SkillMetadata represents all metadata for a published skill
type SkillMetadata struct {
	// Identity
	ID          string    `json:"id"`          // Unique skill ID (hash)
	Name        string    `json:"name"`        // Skill name
	Version     string    `json:"version"`     // Semantic version
	Author      string    `json:"author"`      // Author username
	AuthorID    string    `json:"author_id"`   // Author unique ID

	// Content
	FilePath    string    `json:"file_path"`    // Path to SKILL.md
	Content     string    `json:"content"`     // Markdown content
	Description string    `json:"description"` // Short description

	// Classification
	Category    string   `json:"category"`    // development, sales, ops, etc.
	Tags        []string `json:"tags"`        // User-defined tags
	Tier        string   `json:"tier"`        // utility, specialist, elite

	// Requirements
	ToolsRequired []string `json:"tools_required"` // Required tools
	Compliance    []string `json:"compliance"`     // GDPR, CCPA, etc.

	// Pricing
	Pricing PricingModel `json:"pricing"`

	// Quality
	Quality QualityScore `json:"quality_score"`

	// Status
	Status     string    `json:"status"`     // draft, submitted, approved, live, delisted
	SubmittedAt time.Time `json:"submitted_at"`
	ApprovedAt  time.Time `json:"approved_at"`
	PublishedAt time.Time `json:"published_at"`

	// Stats (updated periodically)
	Stats SkillStats `json:"stats"`
}

// PricingModel defines how the skill is monetized
type PricingModel struct {
	Model      string  `json:"model"`       // per_execution, subscription, free
	CostUSD    float64 `json:"cost_usd"`    // Cost per execution
	FreeTier   int     `json:"free_tier"`   // Free executions per month
	VolumeDiscounts []VolumeDiscount `json:"volume_discounts"`
}

type VolumeDiscount struct {
	MinExecutions int     `json:"min_executions"`
	PriceUSD      float64 `json:"price_usd"`
}

// QualityScore from Signal Theory S/N analysis
type QualityScore struct {
	SNRatio    float64 `json:"s_n_ratio"`    // 0.0 to 1.0
	Rank       string  `json:"rank"`         // optimal, good, pass, fail
	LastCheck  time.Time `json:"last_check"`
	Factors    struct {
		SuccessRate      float64 `json:"success_rate"`
		UserSatisfaction float64 `json:"user_satisfaction"`
		ErrorRate        float64 `json:"error_rate"`
		Efficiency       float64 `json:"efficiency"`
	} `json:"factors"`
}

// SkillStats tracks usage metrics
type SkillStats struct {
	TotalExecutions int64     `json:"total_executions"`
	MonthlyExecutions int64   `json:"monthly_executions"`
	TotalRevenue    float64   `json:"total_revenue"`
	MonthlyRevenue  float64   `json:"monthly_revenue"`
	InstallCount    int       `json:"install_count"`
	ReviewCount     int       `json:"review_count"`
	AverageRating   float64   `json:"average_rating"`
	LastUpdated     time.Time `json:"last_updated"`
}

// Registry manages all published skills
type Registry struct {
	skills map[string]*SkillMetadata
	byAuthor map[string][]string // author_id -> skill IDs
	byCategory map[string][]string // category -> skill IDs
}

// NewRegistry creates a new skill registry
func NewRegistry() *Registry {
	return &Registry{
		skills:     make(map[string]*SkillMetadata),
		byAuthor:   make(map[string][]string),
		byCategory: make(map[string][]string),
	}
}

// GenerateSkillID creates a unique ID from skill content
func GenerateSkillID(author, name, version string) string {
	input := fmt.Sprintf("%s/%s@%s", author, name, version)
	hash := sha256.Sum256([]byte(input))
	return "skill-" + hex.EncodeToString(hash[:])[:12]
}

// Register adds a new skill to the registry
func (r *Registry) Register(skill *SkillMetadata) error {
	if skill.ID == "" {
		skill.ID = GenerateSkillID(skill.Author, skill.Name, skill.Version)
	}

	// Validate required fields
	if err := validateSkill(skill); err != nil {
		return fmt.Errorf("validation failed: %w", err)
	}

	// Check for existing version
	existingKey := fmt.Sprintf("%s/%s@%s", skill.Author, skill.Name, skill.Version)
	if _, exists := r.skills[existingKey]; exists {
		return fmt.Errorf("skill version already exists: %s", existingKey)
	}

	// Set timestamps
	now := time.Now()
	skill.SubmittedAt = now
	if skill.Status == "" {
		skill.Status = "submitted"
	}

	// Store in registry
	r.skills[skill.ID] = skill
	r.byAuthor[skill.AuthorID] = append(r.byAuthor[skill.AuthorID], skill.ID)
	r.byCategory[skill.Category] = append(r.byCategory[skill.Category], skill.ID)

	return nil
}

// Get retrieves a skill by ID
func (r *Registry) Get(id string) (*SkillMetadata, bool) {
	skill, exists := r.skills[id]
	return skill, exists
}

// ListByAuthor returns all skills by an author
func (r *Registry) ListByAuthor(authorID string) []*SkillMetadata {
	ids := r.byAuthor[authorID]
	skills := make([]*SkillMetadata, 0, len(ids))
	for _, id := range ids {
		if skill, exists := r.skills[id]; exists {
			skills = append(skills, skill)
		}
	}
	return skills
}

// ListByCategory returns skills in a category
func (r *Registry) ListByCategory(category string) []*SkillMetadata {
	ids := r.byCategory[category]
	skills := make([]*SkillMetadata, 0, len(ids))
	for _, id := range ids {
		if skill, exists := r.skills[id]; exists {
			skills = append(skills, skill)
		}
	}
	return skills
}

// Search finds skills matching query
type SearchQuery struct {
	Category   string
	Tags       []string
	Tier       string
	MaxPrice   float64
	MinQuality float64
	Free       bool
	Query      string
}

func (r *Registry) Search(q SearchQuery) []*SkillMetadata {
	results := make([]*SkillMetadata, 0)

	for _, skill := range r.skills {
		if !r.matchesQuery(skill, q) {
			continue
		}
		results = append(results, skill)
	}

	return results
}

func (r *Registry) matchesQuery(skill *SkillMetadata, q SearchQuery) bool {
	// Status filter (only show live/approved skills to consumers)
	if skill.Status != "live" && skill.Status != "approved" {
		return false
	}

	// Category filter
	if q.Category != "" && skill.Category != q.Category {
		return false
	}

	// Tier filter
	if q.Tier != "" && skill.Tier != q.Tier {
		return false
	}

	// Price filter
	if q.MaxPrice > 0 && skill.Pricing.CostUSD > q.MaxPrice {
		return false
	}

	// Free filter
	if q.Free && skill.Pricing.CostUSD > 0 {
		return false
	}

	// Quality filter
	if q.MinQuality > 0 && skill.Quality.SNRatio < q.MinQuality {
		return false
	}

	// Tag filter (any match)
	if len(q.Tags) > 0 {
		hasTag := false
		for _, tag := range q.Tags {
			for _, skillTag := range skill.Tags {
				if strings.EqualFold(skillTag, tag) {
					hasTag = true
					break
				}
			}
		}
		if !hasTag {
			return false
		}
	}

	// Text search (name, description)
	if q.Query != "" {
		query := strings.ToLower(q.Query)
		if !strings.Contains(strings.ToLower(skill.Name), query) &&
		   !strings.Contains(strings.ToLower(skill.Description), query) {
			return false
		}
	}

	return true
}

// UpdateQuality updates a skill's quality score
func (r *Registry) UpdateQuality(skillID string, score QualityScore) error {
	skill, exists := r.skills[skillID]
	if !exists {
		return fmt.Errorf("skill not found: %s", skillID)
	}

	skill.Quality = score
	skill.Quality.LastCheck = time.Now()

	// Auto-approve based on quality
	if score.SNRatio >= 0.7 && skill.Status == "submitted" {
		skill.Status = "approved"
		skill.ApprovedAt = time.Now()
	}

	return nil
}

// Publish moves a skill from approved to live
func (r *Registry) Publish(skillID string) error {
	skill, exists := r.skills[skillID]
	if !exists {
		return fmt.Errorf("skill not found: %s", skillID)
	}

	if skill.Status != "approved" {
		return fmt.Errorf("skill must be approved before publishing")
	}

	skill.Status = "live"
	skill.PublishedAt = time.Now()
	return nil
}

// validateSkill checks required fields
func validateSkill(skill *SkillMetadata) error {
	if skill.Name == "" {
		return fmt.Errorf("name is required")
	}
	if skill.Version == "" {
		return fmt.Errorf("version is required")
	}
	if skill.Author == "" {
		return fmt.Errorf("author is required")
	}
	if skill.AuthorID == "" {
		return fmt.Errorf("author_id is required")
	}
	if skill.Category == "" {
		return fmt.Errorf("category is required")
	}
	if skill.Tier == "" {
		return fmt.Errorf("tier is required")
	}
	if skill.Pricing.Model == "" {
		return fmt.Errorf("pricing model is required")
	}
	return nil
}

// ToJSON serializes skill metadata
func (s *SkillMetadata) ToJSON() ([]byte, error) {
	return json.MarshalIndent(s, "", "  ")
}

// FromJSON deserializes skill metadata
func FromJSON(data []byte) (*SkillMetadata, error) {
	var skill SkillMetadata
	err := json.Unmarshal(data, &skill)
	if err != nil {
		return nil, err
	}
	return &skill, nil
}
