package handlers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"task-manager/internal/models"

	"github.com/gorilla/mux"
)

type apiError struct {
	Error     string `json:"error"`
	RequestID string `json:"request_id,omitempty"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, r *http.Request, status int, msg string) {
	rid, _ := r.Context().Value(contextKeyRequestID).(string)
	writeJSON(w, status, apiError{Error: msg, RequestID: rid})
}

func Health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func Ready(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := db.PingContext(r.Context()); err != nil {
			writeError(w, r, http.StatusServiceUnavailable, "database unavailable")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	}
}

func CreateTask(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req models.CreateTaskRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid JSON body")
			return
		}
		if err := req.Validate(); err != nil {
			writeError(w, r, http.StatusBadRequest, err.Error())
			return
		}

		var task models.Task
		err := db.QueryRowContext(r.Context(), `
			INSERT INTO tasks (title, content, due_date, done, last_timestamp)
			VALUES ($1, $2, $3, false, $4)
			RETURNING id, title, content, due_date::text, done, last_timestamp, created_at, updated_at
		`, req.Title, req.Content, req.DueDate, req.RequestTimestamp).
			Scan(&task.ID, &task.Title, &task.Content, &task.DueDate,
				&task.Done, &task.LastTimestamp, &task.CreatedAt, &task.UpdatedAt)

		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "failed to create task")
			return
		}

		writeJSON(w, http.StatusCreated, task)
	}
}

func ListTasks(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(), `
			SELECT id, title, content, due_date::text, done, last_timestamp, created_at, updated_at
			FROM tasks
			ORDER BY created_at DESC
		`)
		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "failed to list tasks")
			return
		}
		defer rows.Close()

		tasks := make([]models.Task, 0)
		for rows.Next() {
			var t models.Task
			if err := rows.Scan(&t.ID, &t.Title, &t.Content, &t.DueDate,
				&t.Done, &t.LastTimestamp, &t.CreatedAt, &t.UpdatedAt); err != nil {
				writeError(w, r, http.StatusInternalServerError, "failed to scan task")
				return
			}
			tasks = append(tasks, t)
		}

		writeJSON(w, http.StatusOK, tasks)
	}
}

func GetTask(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := parseID(r)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid task id")
			return
		}

		var task models.Task
		err = db.QueryRowContext(r.Context(), `
			SELECT id, title, content, due_date::text, done, last_timestamp, created_at, updated_at
			FROM tasks WHERE id = $1
		`, id).Scan(&task.ID, &task.Title, &task.Content, &task.DueDate,
			&task.Done, &task.LastTimestamp, &task.CreatedAt, &task.UpdatedAt)

		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, r, http.StatusNotFound, "task not found")
			return
		}
		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "failed to get task")
			return
		}

		writeJSON(w, http.StatusOK, task)
	}
}

func UpdateTask(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := parseID(r)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid task id")
			return
		}

		var req models.UpdateTaskRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid JSON body")
			return
		}
		if err := req.Validate(); err != nil {
			writeError(w, r, http.StatusBadRequest, err.Error())
			return
		}

		if req.DueDate != nil {
			if _, err := time.Parse("2006-01-02", *req.DueDate); err != nil {
				writeError(w, r, http.StatusBadRequest, "due_date must be in format YYYY-MM-DD")
				return
			}
		}

		result, err := db.ExecContext(r.Context(), `
			UPDATE tasks SET
				title          = COALESCE($1, title),
				content        = COALESCE($2, content),
				due_date       = COALESCE($3::date, due_date),
				done           = COALESCE($4, done),
				last_timestamp = $5,
				updated_at     = NOW()
			WHERE id = $6
			  AND last_timestamp < $5
		`, req.Title, req.Content, req.DueDate, req.Done, req.RequestTimestamp, id)

		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "failed to update task")
			return
		}

		n, _ := result.RowsAffected()
		if n == 0 {
			var exists bool
			db.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM tasks WHERE id=$1)`, id).Scan(&exists)
			if !exists {
				writeError(w, r, http.StatusNotFound, "task not found")
				return
			}
			writeError(w, r, http.StatusConflict, "stale request_timestamp: a newer request has already been processed")
			return
		}

		var task models.Task
		db.QueryRowContext(r.Context(), `
			SELECT id, title, content, due_date::text, done, last_timestamp, created_at, updated_at
			FROM tasks WHERE id = $1
		`, id).Scan(&task.ID, &task.Title, &task.Content, &task.DueDate,
			&task.Done, &task.LastTimestamp, &task.CreatedAt, &task.UpdatedAt)

		writeJSON(w, http.StatusOK, task)
	}
}

func DeleteTask(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := parseID(r)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid task id")
			return
		}

		var req models.DeleteTaskRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid JSON body")
			return
		}
		if err := req.Validate(); err != nil {
			writeError(w, r, http.StatusBadRequest, err.Error())
			return
		}

		result, err := db.ExecContext(r.Context(), `
			DELETE FROM tasks
			WHERE id = $1 AND last_timestamp <= $2
		`, id, req.RequestTimestamp)

		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "failed to delete task")
			return
		}

		n, _ := result.RowsAffected()
		if n == 0 {
			var exists bool
			db.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM tasks WHERE id=$1)`, id).Scan(&exists)
			if !exists {
				writeError(w, r, http.StatusNotFound, "task not found")
				return
			}
			writeError(w, r, http.StatusConflict, "stale request_timestamp: a newer request has already been processed")
			return
		}

		writeJSON(w, http.StatusOK, map[string]string{"message": "task deleted"})
	}
}

func parseID(r *http.Request) (int64, error) {
	vars := mux.Vars(r)
	return strconv.ParseInt(vars["id"], 10, 64)
}
