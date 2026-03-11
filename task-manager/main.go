package main

import (
	"context"
	"crypto/tls"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"task-manager/internal/db"
	"task-manager/internal/handlers"
	"task-manager/internal/middleware"

	"github.com/gorilla/mux"
)

func main() {
	// Database connection
	database, err := db.Connect()
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	// Run migrations
	if err := db.Migrate(database); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}

	// Setup router
	r := mux.NewRouter()

	// Middleware chain
	r.Use(middleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.RateLimit)

	// Health check (no auth)
	r.HandleFunc("/health", handlers.Health).Methods(http.MethodGet)
	r.HandleFunc("/ready", handlers.Ready(database)).Methods(http.MethodGet)

	// Auth endpoint
	r.HandleFunc("/auth/token", handlers.GetToken).Methods(http.MethodPost)

	// Task routes (protected)
	api := r.PathPrefix("/tasks").Subrouter()
	api.Use(middleware.Auth)
	api.HandleFunc("", handlers.CreateTask(database)).Methods(http.MethodPost)
	api.HandleFunc("", handlers.ListTasks(database)).Methods(http.MethodGet)
	api.HandleFunc("/{id}", handlers.GetTask(database)).Methods(http.MethodGet)
	api.HandleFunc("/{id}", handlers.UpdateTask(database)).Methods(http.MethodPut)
	api.HandleFunc("/{id}", handlers.DeleteTask(database)).Methods(http.MethodDelete)

	// TLS config
	tlsConfig := &tls.Config{
		MinVersion: tls.VersionTLS12,
		CipherSuites: []uint16{
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
		},
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8443"
	}

	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")
	if certFile == "" {
		certFile = "/certs/tls.crt"
	}
	if keyFile == "" {
		keyFile = "/certs/tls.key"
	}

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		TLSConfig:    tlsConfig,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		log.Printf("Starting HTTPS server on port %s", port)
		if err := srv.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Server exited cleanly")
}
