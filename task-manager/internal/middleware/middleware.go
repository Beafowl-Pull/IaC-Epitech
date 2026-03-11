package middleware

import (
	"context"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/time/rate"
)

type contextKey string

const (
	contextKeyRequestID contextKey = "request_id"
	contextKeyUserSub   contextKey = "user_sub"
)

func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rid := r.Header.Get("correlation_id")
		if rid == "" {
			rid = r.Header.Get("X-Request-ID")
		}
		if rid == "" {
			rid = generateID()
		}
		ctx := context.WithValue(r.Context(), contextKeyRequestID, rid)
		w.Header().Set("X-Request-ID", rid)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func generateID() string {
	return time.Now().Format("20060102150405.000000000")
}

func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rid, _ := r.Context().Value(contextKeyRequestID).(string)

		rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rw, r)

		log.Printf("[%s] %s %s → %d (%s)", rid, r.Method, r.URL.Path, rw.status, time.Since(start))
	})
}

type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

func Auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			writeError(w, r, http.StatusUnauthorized, "missing or invalid Authorization header")
			return
		}

		tokenStr := strings.TrimPrefix(header, "Bearer ")
		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return jwtSecret(), nil
		})

		if err != nil || !token.Valid {
			writeError(w, r, http.StatusUnauthorized, "invalid or expired token")
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			writeError(w, r, http.StatusUnauthorized, "invalid token claims")
			return
		}

		ctx := context.WithValue(r.Context(), contextKeyUserSub, claims["sub"])
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

var (
	limiters sync.Map
)

type clientLimiter struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

func getLimiter(ip string) *rate.Limiter {
	v, _ := limiters.LoadOrStore(ip, &clientLimiter{
		limiter:  rate.NewLimiter(rate.Every(time.Second), 50), // 50 req/s per IP
		lastSeen: time.Now(),
	})
	cl := v.(*clientLimiter)
	cl.lastSeen = time.Now()
	return cl.limiter
}

func RateLimit(next http.Handler) http.Handler {
	go func() {
		for range time.Tick(5 * time.Minute) {
			limiters.Range(func(k, v interface{}) bool {
				cl := v.(*clientLimiter)
				if time.Since(cl.lastSeen) > 10*time.Minute {
					limiters.Delete(k)
				}
				return true
			})
		}
	}()

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := realIP(r)
		if !getLimiter(ip).Allow() {
			writeError(w, r, http.StatusTooManyRequests, "rate limit exceeded, cluster temporarily overloaded")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func realIP(r *http.Request) string {
	if ip := r.Header.Get("X-Forwarded-For"); ip != "" {
		return strings.Split(ip, ",")[0]
	}
	if ip := r.Header.Get("X-Real-IP"); ip != "" {
		return ip
	}
	return r.RemoteAddr
}

func writeError(w http.ResponseWriter, r *http.Request, status int, msg string) {
	rid, _ := r.Context().Value(contextKeyRequestID).(string)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write([]byte(`{"error":"` + msg + `","request_id":"` + rid + `"}`))
}
