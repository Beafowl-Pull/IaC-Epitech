package models

import "errors"

var (
	ErrMissingTitle     = errors.New("title is required")
	ErrMissingContent   = errors.New("content is required")
	ErrMissingDueDate   = errors.New("due_date is required")
	ErrMissingTimestamp = errors.New("request_timestamp is required")
	ErrInvalidDueDate   = errors.New("due_date must be in format YYYY-MM-DD")
)
