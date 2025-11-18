package log
import ("log/slog"; "os")
var logger *slog.Logger
func Init(level slog.Level) { logger = slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})) }
func L() *slog.Logger { if logger == nil { Init(slog.LevelInfo) }; return logger }
func LevelFromString(s string) slog.Level {
	switch s { case "debug": return slog.LevelDebug; case "warn": return slog.LevelWarn; case "error": return slog.LevelError; default: return slog.LevelInfo }
}
