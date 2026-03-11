package models

import "time"

type Task struct {
	ID        int64     `json:"id" db:"id"`
	Title     string    `json:"title" db:"title"`
	Content   string    `json:"content" db:"content"`
	DueDate   string    `json:"due_date" db:"due_date"`
	Done      bool      `json:"done" db:"done"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
	LastTimestamp time.Time `json:"last_timestamp" db:"last_timestamp"`
}

type CreateTaskRequest struct {
	Title            string    `json:"title"`
	Content          string    `json:"content"`
	DueDate          string    `json:"due_date"`
	RequestTimestamp time.Time `json:"request_timestamp"`
}

type UpdateTaskRequest struct {
	Title            *string   `json:"title"`
	Content          *string   `json:"content"`
	DueDate          *string   `json:"due_date"`
	Done             *bool     `json:"done"`
	RequestTimestamp time.Time `json:"request_timestamp"`
}

type DeleteTaskRequest struct {
	RequestTimestamp time.Time `json:"request_timestamp"`
}

func (r *CreateTaskRequest) Validate() error {
	if r.Title == "" {
		return ErrMissingTitle
	}
	if r.Content == "" {
		return ErrMissingContent
	}
	if r.DueDate == "" {
		return ErrMissingDueDate
	}
	if r.RequestTimestamp.IsZero() {
		return ErrMissingTimestamp
	}
	if _, err := time.Parse("2006-01-02", r.DueDate); err != nil {
		return ErrInvalidDueDate
	}
	return nil
}

func (r *UpdateTaskRequest) Validate() error {
	if r.RequestTimestamp.IsZero() {
		return ErrMissingTimestamp
	}
	return nil
}

func (r *DeleteTaskRequest) Validate() error {
	if r.RequestTimestamp.IsZero() {
		return ErrMissingTimestamp
	}
	return nil
}
