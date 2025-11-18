package log

import (
	"log/slog"
	"os"
)

var logger *slog.Logger

// Init initializes the global logger with a specific level.
func Init(level slog.Level) {
	opts := &slog.HandlerOptions{
		Level: level,
	}
	handler := slog.NewTextHandler(os.Stdout, opts)
	logger = slog.New(handler)
}

// L returns the global logger. It returns a default logger if Init has not been called.
func L() *slog.Logger {
	if logger == nil {
		// Default logger if Init is not called.
		Init(slog.LevelInfo)
	}
	return logger
}

// LevelFromString converts a string to a slog.Level.
func LevelFromString(levelStr string) slog.Level {
	switch levelStr {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
