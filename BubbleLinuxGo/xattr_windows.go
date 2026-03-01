//go:build windows

package main

import (
	"fmt"
)

func writeMetadata(path string, res *TagResult) error {
	// Extended attributes (xattrs) are not natively supported in a portable way on Windows.
	// For now, we skip writing them, but functionality remains via the .bubble/summaries.json file.
	return nil
}

func getMetadata(path string) (*FileMetadata, error) {
	// Since we don't write xattrs on Windows, we return an error to indicate no such metadata.
	// The application will rely on the local .bubble/summaries.json instead.
	return nil, fmt.Errorf("metadata not supported on Windows")
}
