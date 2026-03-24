package api

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"canopy/marketplace/quality"
	"canopy/marketplace/registry"
)

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLISH API — Skill publishing and marketplace submission
// ═══════════════════════════════════════════════════════════════════════════════

// Publisher handles skill publication workflow
type Publisher struct {
	registry     *registry.Registry
	qualityGate  *quality.QualityGate
	marketplaceDir string
}

// PublishRequest represents a skill submission
type PublishRequest struct {
	SkillPath  string              `json:"skill_path"`  // Path to SKILL.md
	AuthorID   string              `json:"author_id"`   // Author unique ID
	Category   string              `json:"category"`    // Skill category
	Pricing    registry.PricingModel `json:"pricing"`    // Pricing model
}

// PublishResponse contains submission result
type PublishResponse struct {
	Success     bool              `json:"success"`
	SkillID     string            `json:"skill_id"`
	Status      string            `json:"status"`
	QualityScore quality.QualityScore `json:"quality_score"`
	Message     string            `json:"message"`
}

// NewPublisher creates a new publisher
func NewPublisher(reg *registry.Registry, qg *quality.QualityGate, marketplaceDir string) *Publisher {
	return &Publisher{
		registry:       reg,
		qualityGate:    qg,
		marketplaceDir: marketplaceDir,
	}
}

// Publish submits a skill to the marketplace
func (p *Publisher) Publish(req PublishRequest) (*PublishResponse, error) {
	// 1. Read skill file
	content, err := os.ReadFile(req.SkillPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read skill file: %w", err)
	}

	// 2. Parse frontmatter metadata
	metadata, err := parseSkillFrontmatter(string(content))
	if err != nil {
		return nil, fmt.Errorf("failed to parse skill metadata: %w", err)
	}

	// 3. Build skill metadata
	skill := &registry.SkillMetadata{
		FilePath:    req.SkillPath,
		Content:     string(content),
		AuthorID:    req.AuthorID,
		Category:    req.Category,
		Pricing:     req.Pricing,
		Status:      "submitted",
	}

	// Extract from frontmatter
	if name, ok := metadata["name"].(string); ok {
		skill.Name = name
	}
	if version, ok := metadata["version"].(string); ok {
		skill.Version = version
	}
	if author, ok := metadata["author"].(string); ok {
		skill.Author = author
	}
	if desc, ok := metadata["description"].(string); ok {
		skill.Description = desc
	}
	if tier, ok := metadata["tier"].(string); ok {
		skill.Tier = tier
	}
	if tags, ok := metadata["tags"].([]interface{}); ok {
		for _, t := range tags {
			if tag, ok := t.(string); ok {
				skill.Tags = append(skill.Tags, tag)
			}
		}
	}

	// 4. Run quality gate
	score, err := p.qualityGate.Evaluate(skill.Content, metadata)
	if err != nil {
		return nil, fmt.Errorf("quality evaluation failed: %w", err)
	}
	skill.Quality = score

	// 5. Auto-approve if quality passes
	if score.SNRatio >= 0.7 {
		skill.Status = "approved"
	}

	// 6. Register in marketplace
	if err := p.registry.Register(skill); err != nil {
		return nil, fmt.Errorf("registration failed: %w", err)
	}

	// 7. Copy to marketplace registry
	if err := p.copyToMarketplace(skill); err != nil {
		return nil, fmt.Errorf("failed to copy to marketplace: %w", err)
	}

	// 8. Build response
	response := &PublishResponse{
		Success:     true,
		SkillID:     skill.ID,
		Status:      skill.Status,
		QualityScore: score,
	}

	if skill.Status == "approved" {
		response.Message = fmt.Sprintf("✅ Skill approved! S/N score: %.2f. Ready to publish.", score.SNRatio)
	} else {
		response.Message = fmt.Sprintf("⚠️  Skill submitted for review. S/N score: %.2f. Needs improvements.", score.SNRatio)
	}

	return response, nil
}

// ListMySkills returns all skills by an author
func (p *Publisher) ListMySkills(authorID string) ([]*registry.SkillMetadata, error) {
	skills := p.registry.ListByAuthor(authorID)
	return skills, nil
}

// GetSkill retrieves a skill by ID
func (p *Publisher) GetSkill(skillID string) (*registry.SkillMetadata, error) {
	skill, exists := p.registry.Get(skillID)
	if !exists {
		return nil, fmt.Errorf("skill not found: %s", skillID)
	}
	return skill, nil
}

// PublishSkill moves an approved skill to live
func (p *Publisher) PublishSkill(skillID string) error {
	return p.registry.Publish(skillID)
}

// copyToMarketplace copies skill file to marketplace registry
func (p *Publisher) copyToMarketplace(skill *registry.SkillMetadata) error {
	// Create marketplace directory
	targetDir := filepath.Join(p.marketplaceDir, "skills", skill.Author, skill.Name)
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return err
	}

	// Copy skill file
	targetPath := filepath.Join(targetDir, fmt.Sprintf("%s.md", skill.Version))
	if err := os.WriteFile(targetPath, []byte(skill.Content), 0644); err != nil {
		return err
	}

	// Write metadata
	metadataPath := filepath.Join(targetDir, fmt.Sprintf("%s.metadata.json", skill.Version))
	metadataJSON, err := skill.ToJSON()
	if err != nil {
		return err
	}

	if err := os.WriteFile(metadataPath, metadataJSON, 0644); err != nil {
		return err
	}

	return nil
}

// parseSkillFrontmatter extracts YAML frontmatter from skill file
func parseSkillFrontmatter(content string) (map[string]interface{}, error) {
	lines := make([]string, 0)
	inFrontmatter := false
	frontmatterClosed := false

	for _, line := range splitLines(content) {
		trimmed := trimSpace(line)

		// Start of frontmatter
		if trimmed == "---" {
			if !inFrontmatter {
				inFrontmatter = true
				continue
			} else if !frontmatterClosed {
				frontmatterClosed = true
				break
			}
		}

		if inFrontmatter {
			lines = append(lines, line)
		}
	}

	if !frontmatterClosed {
		return nil, fmt.Errorf("no valid frontmatter found")
	}

	// Simple YAML parsing (in production, use gopkg.in/yaml.v3)
	metadata := make(map[string]interface{})
	for _, line := range lines {
		if idx := indexOf(line, ":"); idx > 0 {
			key := trimSpace(line[:idx])
			value := trimSpace(line[idx+1:])
			metadata[key] = value
		}
	}

	return metadata, nil
}

// Helper functions
func splitLines(s string) []string {
	lines := make([]string, 0)
	current := ""
	for _, ch := range s {
		if ch == '\n' {
			lines = append(lines, current)
			current = ""
		} else {
			current += string(ch)
		}
	}
	if current != "" {
		lines = append(lines, current)
	}
	return lines
}

func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n') {
		end--
	}
	return s[start:end]
}

func indexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
