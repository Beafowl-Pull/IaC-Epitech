package db

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	_ "github.com/lib/pq"
)

func Connect() (*sql.DB, error) {
	dsn := buildDSN()
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open db: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetConnMaxIdleTime(2 * time.Minute)

	for i := 0; i < 10; i++ {
		if err = db.Ping(); err == nil {
			log.Println("Database connected successfully")
			return db, nil
		}
		log.Printf("Database not ready, retrying in 3s... (%d/10)", i+1)
		time.Sleep(3 * time.Second)
	}

	return nil, fmt.Errorf("failed to ping database after retries: %w", err)
}

func buildDSN() string {
	socketDir := os.Getenv("DB_SOCKET_DIR")
	if socketDir != "" {
		instance := os.Getenv("DB_INSTANCE")
		return fmt.Sprintf(
			"host=%s/%s user=%s password=%s dbname=%s sslmode=disable",
			socketDir, instance,
			os.Getenv("DB_USER"),
			os.Getenv("DB_PASSWORD"),
			os.Getenv("DB_NAME"),
		)
	}

	host := os.Getenv("DB_HOST")
	if host == "" {
		host = "localhost"
	}
	port := os.Getenv("DB_PORT")
	if port == "" {
		port = "5432"
	}
	sslMode := os.Getenv("DB_SSL_MODE")
	if sslMode == "" {
		sslMode = "require"
	}

	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port,
		os.Getenv("DB_USER"),
		os.Getenv("DB_PASSWORD"),
		os.Getenv("DB_NAME"),
		sslMode,
	)
}

func Migrate(db *sql.DB) error {
	query := `
	CREATE TABLE IF NOT EXISTS tasks (
		id               BIGSERIAL PRIMARY KEY,
		title            TEXT        NOT NULL,
		content          TEXT        NOT NULL,
		due_date         DATE        NOT NULL,
		done             BOOLEAN     NOT NULL DEFAULT FALSE,
		last_timestamp   TIMESTAMPTZ NOT NULL,
		created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE INDEX IF NOT EXISTS idx_tasks_last_timestamp ON tasks(last_timestamp);
	CREATE INDEX IF NOT EXISTS idx_tasks_due_date       ON tasks(due_date);
	CREATE INDEX IF NOT EXISTS idx_tasks_done           ON tasks(done);
	`

	if _, err := db.Exec(query); err != nil {
		return fmt.Errorf("migration failed: %w", err)
	}

	log.Println("Database migration completed")
	return nil
}
