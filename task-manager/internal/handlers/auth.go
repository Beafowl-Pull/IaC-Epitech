package handlers

import (
	"encoding/json"
	"net/http"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type tokenRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type tokenResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

func GetToken(w http.ResponseWriter, r *http.Request) {
	var req tokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid JSON body")
		return
	}

	validUser := os.Getenv("API_USERNAME")
	validPass := os.Getenv("API_PASSWORD")
	if validUser == "" {
		validUser = "admin"
	}

	if req.Username != validUser || req.Password != validPass {
		writeError(w, r, http.StatusUnauthorized, "invalid credentials")
		return
	}

	secret := jwtSecret()
	expiresAt := time.Now().Add(24 * time.Hour)

	claims := jwt.MapClaims{
		"sub": req.Username,
		"iat": time.Now().Unix(),
		"exp": expiresAt.Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(secret)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, "failed to generate token")
		return
	}

	writeJSON(w, http.StatusOK, tokenResponse{
		Token:     signed,
		ExpiresAt: expiresAt,
	})
}

func jwtSecret() []byte {
	s := os.Getenv("JWT_SECRET")
	if s == "" {
		s = "change-me-in-production-use-a-strong-secret"
	}
	return []byte(s)
}
