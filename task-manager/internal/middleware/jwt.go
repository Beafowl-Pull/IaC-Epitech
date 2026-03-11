package middleware

import "os"

func jwtSecret() []byte {
	s := os.Getenv("JWT_SECRET")
	if s == "" {
		s = "change-me-in-production-use-a-strong-secret"
	}
	return []byte(s)
}
