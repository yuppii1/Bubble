package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// --- Common Models ---

type LLMConfiguration struct {
	APIKey string
	Model  string
}

type TagResult struct {
	Summary  string
	Keywords []string
}

type FileMetadata struct {
	Path    string   `json:"path"`
	Summary string   `json:"summary"`
	Tags    []string `json:"tags"`
}

// --- Configuration Persistence ---

type Config struct {
	Providers map[string]ProviderConfig `json:"providers"`
	Active    string                    `json:"active_provider"`
}

type ProviderConfig struct {
	APIKey string `json:"api_key"`
	Model  string `json:"model"`
}

func getConfigPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".bubble_config.json")
}

func loadConfig() *Config {
	path := getConfigPath()
	data, err := os.ReadFile(path)
	if err != nil {
		return &Config{Providers: make(map[string]ProviderConfig)}
	}
	var conf Config
	json.Unmarshal(data, &conf)
	if conf.Providers == nil {
		conf.Providers = make(map[string]ProviderConfig)
	}
	return &conf
}

func saveConfig(conf *Config) error {
	path := getConfigPath()
	data, err := json.MarshalIndent(conf, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}
