//go:build linux || darwin

package main

import (
	"fmt"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

func writeMetadata(path string, res *TagResult) error {
	// Use 'user.' namespace for Linux extended attributes
	summaryKey := "user.summary"
	keywordsKey := "user.keywords"
	lastProcessedKey := "user.last_processed"

	err := unix.Setxattr(path, summaryKey, []byte(res.Summary), 0)
	if err != nil {
		return fmt.Errorf("failed to set summary xattr: %w", err)
	}

	keywordsStr := strings.Join(res.Keywords, ", ")
	err = unix.Setxattr(path, keywordsKey, []byte(keywordsStr), 0)
	if err != nil {
		return fmt.Errorf("failed to set keywords xattr: %w", err)
	}

	timestamp := time.Now().Format(time.RFC3339)
	err = unix.Setxattr(path, lastProcessedKey, []byte(timestamp), 0)
	if err != nil {
		return fmt.Errorf("failed to set last_processed xattr: %w", err)
	}

	return nil
}

func getMetadata(path string) (*FileMetadata, error) {
	summary := ""
	tags := []string{}

	// Try reading Finder comments or user.summary
	data, err := getXattr(path, "com.apple.metadata:kMDItemFinderComment")
	if err == nil {
		summary = string(data)
	} else {
		data, err = getXattr(path, "user.summary")
		if err == nil {
			summary = string(data)
		}
	}

	data, err = getXattr(path, "user.keywords")
	if err == nil {
		tagStr := string(data)
		parts := strings.Split(tagStr, ",")
		for _, p := range parts {
			t := strings.TrimSpace(p)
			if t != "" {
				tags = append(tags, t)
			}
		}
	}

	if summary == "" && len(tags) == 0 {
		return nil, fmt.Errorf("no metadata found")
	}

	return &FileMetadata{
		Path:    path,
		Summary: summary,
		Tags:    tags,
	}, nil
}

func getXattr(path, attr string) ([]byte, error) {
	size, err := unix.Getxattr(path, attr, nil)
	if err != nil || size <= 0 {
		return nil, err
	}
	dest := make([]byte, size)
	_, err = unix.Getxattr(path, attr, dest)
	if err != nil {
		return nil, err
	}
	return dest, nil
}
