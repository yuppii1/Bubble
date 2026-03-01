package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// --- LLM Providers ---

type LLMProvider string

const (
	ProviderGemini    LLMProvider = "gemini"
	ProviderOpenAI    LLMProvider = "openai"
	ProviderAnthropic LLMProvider = "anthropic"
)

// --- LLM Services ---

type LLMService interface {
	GenerateTags(text string, config LLMConfiguration) (*TagResult, error)
}

// Gemini logic
type GeminiService struct{}

func (s *GeminiService) GenerateTags(text string, config LLMConfiguration) (*TagResult, error) {
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", config.Model, config.APIKey)

	prompt := fmt.Sprintf(`Analyze the following file content. Provide:
1. A concise summary (max 2 sentences).
2. A list of 5-10 relevant keywords/tags (comma-separated).

Format the output exactly like this:
Summary: [Your summary here]
Tags: [tag1, tag2, tag3]

Content:
%s`, truncateText(text, 10000))

	payload := map[string]interface{}{
		"contents": []interface{}{
			map[string]interface{}{
				"parts": []interface{}{
					map[string]interface{}{"text": prompt},
				},
			},
		},
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(data))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("gemini api error (status %d): %s", resp.StatusCode, string(body))
	}

	var result struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	if len(result.Candidates) == 0 || len(result.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("empty response from Gemini")
	}

	return parseResponse(result.Candidates[0].Content.Parts[0].Text), nil
}

// OpenAI logic
type OpenAIService struct{}

func (s *OpenAIService) GenerateTags(text string, config LLMConfiguration) (*TagResult, error) {
	url := "https://api.openai.com/v1/chat/completions"

	prompt := fmt.Sprintf(`Analyze the following file content. Provide:
1. A concise summary (max 2 sentences).
2. A list of 5-10 relevant keywords/tags (comma-separated).

Format the output exactly like this:
Summary: [Your summary here]
Tags: [tag1, tag2, tag3]

Content:
%s`, truncateText(text, 15000))

	payload := map[string]interface{}{
		"model": config.Model,
		"messages": []interface{}{
			map[string]string{"role": "user", "content": prompt},
		},
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+config.APIKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("openai api error (status %d): %s", resp.StatusCode, string(body))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	if len(result.Choices) == 0 {
		return nil, fmt.Errorf("empty response from OpenAI")
	}

	return parseResponse(result.Choices[0].Message.Content), nil
}

// Anthropic logic
type AnthropicService struct{}

func (s *AnthropicService) GenerateTags(text string, config LLMConfiguration) (*TagResult, error) {
	url := "https://api.anthropic.com/v1/messages"

	prompt := fmt.Sprintf(`Analyze the following file content. Provide:
1. A concise summary (max 2 sentences).
2. A list of 5-10 relevant keywords/tags (comma-separated).

Format the output exactly like this:
Summary: [Your summary here]
Tags: [tag1, tag2, tag3]

Content:
%s`, truncateText(text, 30000))

	payload := map[string]interface{}{
		"model":      config.Model,
		"max_tokens": 1024,
		"messages": []interface{}{
			map[string]string{"role": "user", "content": prompt},
		},
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", config.APIKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("anthropic api error (status %d): %s", resp.StatusCode, string(body))
	}

	var result struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	if len(result.Content) == 0 {
		return nil, fmt.Errorf("empty response from Anthropic")
	}

	return parseResponse(result.Content[0].Text), nil
}

// --- Utils ---

func truncateText(text string, maxLen int) string {
	if len(text) > maxLen {
		return text[:maxLen]
	}
	return text
}

func parseResponse(text string) *TagResult {
	result := &TagResult{}
	lines := strings.Split(text, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Summary:") {
			result.Summary = strings.TrimSpace(strings.TrimPrefix(line, "Summary:"))
		} else if strings.HasPrefix(line, "Tags:") {
			tagsStr := strings.TrimSpace(strings.TrimPrefix(line, "Tags:"))
			tagsStr = strings.Trim(tagsStr, "[]")
			parts := strings.Split(tagsStr, ",")
			for _, p := range parts {
				tag := strings.TrimSpace(p)
				if tag != "" {
					result.Keywords = append(result.Keywords, tag)
				}
			}
		}
	}

	if result.Summary == "" && len(text) > 0 {
		if len(text) > 200 {
			result.Summary = text[:200]
		} else {
			result.Summary = text
		}
	}

	return result
}

// --- Persistence ---

type FileSummary struct {
	Summary          string    `json:"summary"`
	Keywords         []string  `json:"keywords"`
	LastProcessed    time.Time `json:"lastProcessed"`
	FileSize         int64     `json:"fileSize"`
	ModificationDate time.Time `json:"modificationDate"`
}

type ProjectSummary struct {
	Files map[string]FileSummary `json:"files"`
}

func saveProjectSummary(root string, summary *ProjectSummary) error {
	bubbleDir := filepath.Join(root, ".bubble")
	if err := os.MkdirAll(bubbleDir, 0755); err != nil {
		return err
	}

	path := filepath.Join(bubbleDir, "summaries.json")
	data, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

func loadProjectSummary(root string) *ProjectSummary {
	path := filepath.Join(root, ".bubble", "summaries.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return &ProjectSummary{Files: make(map[string]FileSummary)}
	}
	var summary ProjectSummary
	json.Unmarshal(data, &summary)
	if summary.Files == nil {
		summary.Files = make(map[string]FileSummary)
	}
	return &summary
}

// --- MCP Server Implementation ---

type MCPRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

type MCPResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id"`
	Result  interface{} `json:"result,omitempty"`
	Error   interface{} `json:"error,omitempty"`
}

func runMCPServer() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var req MCPRequest
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			continue
		}

		var resp MCPResponse
		resp.JSONRPC = "2.0"
		resp.ID = req.ID

		switch req.Method {
		case "initialize":
			resp.Result = map[string]interface{}{
				"protocolVersion": "2024-11-05",
				"capabilities":    map[string]interface{}{},
				"serverInfo": map[string]string{
					"name":    "bubble-mcp",
					"version": "1.0.0",
				},
			}
		case "listTools":
			resp.Result = map[string]interface{}{
				"tools": []interface{}{
					map[string]interface{}{
						"name":        "get_file_summary",
						"description": "Get the AI-generated summary and tags for a specific file.",
						"inputSchema": map[string]interface{}{
							"type": "object",
							"properties": map[string]interface{}{
								"path": map[string]string{"type": "string"},
							},
							"required": []string{"path"},
						},
					},
					map[string]interface{}{
						"name":        "get_latest_pasted_image",
						"description": "Get the path to the most recently pasted/saved image in the Bubble directory.",
						"inputSchema": map[string]interface{}{
							"type":       "object",
							"properties": map[string]interface{}{},
						},
					},
				},
			}
		case "callTool":
			var params struct {
				Name      string          `json:"name"`
				Arguments json.RawMessage `json:"arguments"`
			}
			json.Unmarshal(req.Params, &params)

			switch params.Name {
			case "get_file_summary":
				var args struct {
					Path string `json:"path"`
				}
				json.Unmarshal(params.Arguments, &args)
				meta, err := getMetadata(args.Path)
				if err != nil {
					resp.Result = map[string]interface{}{"content": []interface{}{map[string]string{"type": "text", "text": "Error: " + err.Error()}}}
				} else {
					text := fmt.Sprintf("Summary: %s\nTags: %s", meta.Summary, strings.Join(meta.Tags, ", "))
					resp.Result = map[string]interface{}{"content": []interface{}{map[string]string{"type": "text", "text": text}}}
				}
			case "get_latest_pasted_image":
				home, _ := os.UserHomeDir()
				// Default path as used in the Swift app
				imageDir := filepath.Join(home, "Pictures", "Bubble")

				files, err := os.ReadDir(imageDir)
				if err != nil || len(files) == 0 {
					resp.Result = map[string]interface{}{"content": []interface{}{map[string]string{"type": "text", "text": "Error: No images found or directory does not exist."}}}
				} else {
					var latestFile os.DirEntry
					var latestTime time.Time

					for _, f := range files {
						if !f.IsDir() {
							info, _ := f.Info()
							if info.ModTime().After(latestTime) {
								latestTime = info.ModTime()
								latestFile = f
							}
						}
					}

					if latestFile == nil {
						resp.Result = map[string]interface{}{"content": []interface{}{map[string]string{"type": "text", "text": "Error: No valid image files found."}}}
					} else {
						fullPath := filepath.Join(imageDir, latestFile.Name())
						resp.Result = map[string]interface{}{"content": []interface{}{map[string]string{"type": "text", "text": fullPath}}}
					}
				}
			}
		default:
			resp.Result = map[string]interface{}{}
		}

		out, _ := json.Marshal(resp)
		fmt.Println(string(out))
	}
}

// --- Main execution ---

func main() {
	folder := flag.String("folder", ".", "The directory to scan")
	providerStr := flag.String("provider", "", "LLM provider (gemini, openai, anthropic)")
	apiKey := flag.String("api-key", "", "API Key for your chosen provider")
	model := flag.String("model", "", "Model name (override default)")
	verbose := flag.Bool("verbose", false, "Show detailed output")
	save := flag.Bool("save", false, "Save the provided API key and provider as default")
	metadata := flag.String("metadata", "", "Read and print metadata for a file or directory")
	mcp := flag.Bool("mcp", false, "Run as an MCP server")
	flag.Parse()

	// MCP Mode
	if *mcp {
		runMCPServer()
		return
	}

	// Metadata Mode
	if *metadata != "" {
		info, err := os.Stat(*metadata)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

		if info.IsDir() {
			filepath.WalkDir(*metadata, func(path string, d fs.DirEntry, err error) error {
				if err == nil && !d.IsDir() {
					if meta, err := getMetadata(path); err == nil {
						fmt.Printf("[%s]\nSummary: %s\nTags: %s\n\n", path, meta.Summary, strings.Join(meta.Tags, ", "))
					}
				}
				return nil
			})
		} else {
			meta, err := getMetadata(*metadata)
			if err != nil {
				fmt.Printf("Error: %v\n", err)
				os.Exit(1)
			}
			fmt.Printf("Summary: %s\nTags: %s\n", meta.Summary, strings.Join(meta.Tags, ", "))
		}
		return
	}

	conf := loadConfig()

	// 1. Determine Provider
	finalProvider := *providerStr
	if finalProvider == "" {
		if conf.Active != "" {
			finalProvider = conf.Active
		} else {
			finalProvider = "gemini"
		}
	}

	// 2. Determine API Key and Model
	finalKey := *apiKey
	finalModel := *model

	providerConf, exists := conf.Providers[finalProvider]
	if finalKey == "" && exists {
		finalKey = providerConf.APIKey
	}
	if finalModel == "" && exists {
		finalModel = providerConf.Model
	}

	if finalKey == "" {
		fmt.Printf("Error: API Key is required for provider '%s'. Use --api-key or run with --save to persist it.\n", finalProvider)
		os.Exit(1)
	}

	var service LLMService
	var defaultModel string

	switch LLMProvider(finalProvider) {
	case ProviderGemini:
		service = &GeminiService{}
		defaultModel = "gemini-2.5-flash"
	case ProviderOpenAI:
		service = &OpenAIService{}
		defaultModel = "gpt-4o-mini"
	case ProviderAnthropic:
		service = &AnthropicService{}
		defaultModel = "claude-3-5-sonnet-20241022"
	default:
		fmt.Printf("Error: Unknown provider '%s'\n", finalProvider)
		os.Exit(1)
	}

	if finalModel == "" {
		finalModel = defaultModel
	}

	// Save if requested
	if *save {
		conf.Active = finalProvider
		conf.Providers[finalProvider] = ProviderConfig{
			APIKey: finalKey,
			Model:  finalModel,
		}
		if err := saveConfig(conf); err != nil {
			fmt.Printf("Warning: Failed to save config: %v\n", err)
		} else {
			fmt.Println("✅ Configuration saved to ~/.bubble_config.json")
		}
	}

	config := LLMConfiguration{
		APIKey: finalKey,
		Model:  finalModel,
	}

	ignoreDirs := map[string]bool{
		".git":          true,
		".gemini":       true,
		".bubble":       true,
		"node_modules":  true,
		"build":         true,
		"dist":          true,
		"AITaggerLinux": true,
		"BubbleLinux":   true,
	}
	ignoreExts := map[string]bool{
		".png": true, ".jpg": true, ".jpeg": true, ".gif": true,
		".pdf": true, ".zip": true, ".tar": true, ".gz": true,
		".exe": true, ".dll": true, ".so": true, ".o": true,
	}

	var filesToProcess []string
	err := filepath.WalkDir(*folder, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if ignoreDirs[d.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ignoreExts[ext] {
			return nil
		}
		filesToProcess = append(filesToProcess, path)
		return nil
	})

	if err != nil {
		fmt.Printf("Error scanning directory: %v\n", err)
		os.Exit(1)
	}

	// Load existing summaries
	projectSummary := loadProjectSummary(*folder)

	var filesToProcessFiltered []string
	filesToSkip := 0

	for _, path := range filesToProcess {
		relPath, _ := filepath.Rel(*folder, path)
		info, err := os.Stat(path)
		if err == nil {
			if existing, exists := projectSummary.Files[relPath]; exists {
				if existing.ModificationDate.Equal(info.ModTime()) && existing.FileSize == info.Size() {
					filesToSkip++
					continue
				}
			}
		}
		filesToProcessFiltered = append(filesToProcessFiltered, path)
	}

	fmt.Printf("Found %d new/updated files (skipped %d).\n", len(filesToProcessFiltered), filesToSkip)

	if len(filesToProcessFiltered) == 0 {
		fmt.Println("Everything up to date.")
		return
	}

	fmt.Printf("Using %s provider with model %s\n", finalProvider, finalModel)

	for i, path := range filesToProcessFiltered {
		if *verbose {
			fmt.Printf("[%d/%d] Processing %s...\n", i+1, len(filesToProcessFiltered), filepath.Base(path))
		}

		content, err := os.ReadFile(path)
		if err != nil {
			fmt.Printf("❌ Failed to read %s: %v\n", path, err)
			continue
		}

		// Sleep to avoid rate limits
		if LLMProvider(finalProvider) == ProviderGemini {
			time.Sleep(1 * time.Second)
		}

		res, err := service.GenerateTags(string(content), config)
		if err != nil {
			fmt.Printf("❌ Failed to process %s: %v\n", path, err)
			continue
		}

		if err := writeMetadata(path, res); err != nil {
			fmt.Printf("❌ Failed to write metadata for %s: %v\n", path, err)
			continue
		}

		// Update persistence
		relPath, _ := filepath.Rel(*folder, path)
		info, _ := os.Stat(path)
		projectSummary.Files[relPath] = FileSummary{
			Summary:          res.Summary,
			Keywords:         res.Keywords,
			LastProcessed:    time.Now(),
			FileSize:         info.Size(),
			ModificationDate: info.ModTime(),
		}

		// Save periodically
		if (i+1)%5 == 0 || i == len(filesToProcessFiltered)-1 {
			saveProjectSummary(*folder, projectSummary)
		}

		fmt.Printf("✅ Tagged: %s\n", filepath.Base(path))
	}

	fmt.Println("Scan Complete!")
}
