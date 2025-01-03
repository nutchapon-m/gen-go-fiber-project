# Initialize Go module
echo "Initializing Go module..."
echo
read -p "Enter project name: " PROJECT_NAME
echo
go mod init "$PROJECT_NAME"
echo
echo "Install Packages..."
go get -u gorm.io/gorm
go get go.uber.org/zap
go get github.com/spf13/viper
go get github.com/golang-jwt/jwt/v5
go get github.com/gofiber/fiber/v2
echo
# Create directories
echo "Creating directories..."
mkdir -p cmd configs external/db internal/{core/{domains,services},handlers,pkgs/{errs,logs,utils},repositories} app/{middlewares,api}
# Create files and add content
echo "Creating and populating files..."
# main.go
cat <<EOF > main.go
package main

import (
	"$PROJECT_NAME/app/middlewares"
	"$PROJECT_NAME/configs"
	"$PROJECT_NAME/internal/pkgs/logs"

	"fmt"
	"log"
	"os"
	"os/signal"

	"github.com/gofiber/fiber/v2"
	"github.com/spf13/viper"
)

func init() {
	configs.Init()
	logs.LogInit()
}

func main() {
	app := fiber.New(fiber.Config{
		AppName: "atelnord",
	})

	app.Use(
		middlewares.NewLoggerMiddleware,
		middlewares.NewCorsMiddleware,
	)
	// Gracefully shutting down
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	go func() {
		serv := <-c
		if serv.String() == "interrupt" {
			fmt.Println("Gracefully shutting down...")
			app.Shutdown()
		}
	}()

	if viper.GetString("server.mode") == "debug" {
		err := app.Listen("localhost:" + viper.GetString("server.port"))
		if err != nil {
			log.Fatal(err)
		}
	} else {
		err := app.Listen(":" + viper.GetString("server.port"))
		if err != nil {
			log.Fatal(err)
		}
	}
}
EOF

# configs.go
cat <<EOF > configs/configs.go
package configs

import (
    "fmt"
    "os"
    "strings"
    "time"

    "github.com/spf13/viper"
)

func Init() {
    initConfigLoader()
    initTimeZone()
}

func initConfigLoader() {
    viper.SetConfigName("config")
    viper.SetConfigType("yml")
    viper.AddConfigPath(".")
    viper.AutomaticEnv()
    viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

    viper.ReadInConfig()
}

func initTimeZone() {
    ict, err := time.LoadLocation("Asia/Bangkok")
    if err != nil {
    fmt.Printf("Error: %v\n", err)
    os.Exit(1)
    }
    time.Local = ict
}
EOF

# logger.go
LOG_FORMAT="[\${time}] | \${status} | \${latency} | \${ip} | \${method} | \${path} | \${error}\\n"

cat <<EOF > app/middlewares/log.go
package middlewares

import (
	"os"
	"time"

	"github.com/gofiber/fiber/v2/middleware/logger"
)

var NewLoggerMiddleware = logger.New(logger.Config{
	Next:          nil,
	Done:          nil,
	Format:        "$LOG_FORMAT",
	TimeFormat:    "2006-01-02 15:04:05",
	TimeZone:      "Local",
	TimeInterval:  500 * time.Millisecond,
	Output:        os.Stdout,
	DisableColors: false,
})
EOF

# cors.go
cat <<EOF > app/middlewares/cors.go
package middlewares

import (
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
)

var NewCorsMiddleware = cors.New(cors.Config{
	Next:             nil,
	AllowOriginsFunc: nil,
	AllowOrigins:     "*",
	AllowMethods: strings.Join([]string{
		fiber.MethodGet,
		fiber.MethodPost,
		fiber.MethodPut,
		fiber.MethodDelete,
		fiber.MethodPatch,
	}, ","),
	AllowHeaders:     "",
	AllowCredentials: false,
	ExposeHeaders:    "",
	MaxAge:           0,
})
EOF

# logs.go
cat <<EOF > internal/pkgs/logs/logs.go
package logs

import (
	"github.com/spf13/viper"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var (
	log    *zap.Logger
	config zap.Config
	err    error
)

func LogInit() {
	if viper.GetString("server.mode") == "debug" {
		config = zap.NewDevelopmentConfig()
	} else {
		config = zap.NewProductionConfig()
	}

	config.EncoderConfig.TimeKey = "timestamp"
	config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	config.EncoderConfig.StacktraceKey = ""

	log, err = config.Build(zap.AddCallerSkip(1))
	if err != nil {
		panic(err)
	}
}

func Info(message string, field ...zapcore.Field) {
	log.Info(message, field...)
}

func Debug(message string, field ...zapcore.Field) {
	log.Debug(message, field...)
}
func Error(message interface{}, field ...zapcore.Field) {
	switch v := message.(type) {
	case error:
		log.Error(v.Error(), field...)
	case string:
		log.Error(v, field...)
	}
}
EOF

# errs.go
cat <<EOF > internal/pkgs/errs/errs.go
package errs

import "github.com/gofiber/fiber/v2"

type AppError struct {
	Code    int
	Message string
}

func (e AppError) Error() string {
	return e.Message
}

func NewError(msg string) error {
	return AppError{
		Code:    fiber.ErrBadRequest.Code,
		Message: msg,
	}
}

func NewNotfoundError(msg string) error {
	return AppError{
		Code:    fiber.ErrNotFound.Code,
		Message: msg,
	}
}

func NewUnexpectedError(msg string) error {
	return AppError{
		Code:    fiber.ErrInternalServerError.Code,
		Message: msg,
	}
}

func NewNotAcceptableError(msg string) error {
	return AppError{
		Code:    fiber.ErrNotAcceptable.Code,
		Message: msg,
	}
}

func NewTooManyArgumentsToFunction() error {
	return AppError{
		Code:    fiber.ErrInternalServerError.Code,
		Message: "Too many arguments to function.",
	}
}

func NewUnauthorizedError() error {
	return AppError{
		Code:    fiber.ErrUnauthorized.Code,
		Message: fiber.ErrUnauthorized.Message,
	}
}

func NewExitingDataError(msg string) error {
	return AppError{
		Code:    fiber.ErrNotAcceptable.Code,
		Message: msg,
	}
}

func NewValidateError(msg string) error {
	return AppError{
		Code:    fiber.ErrBadRequest.Code,
		Message: msg,
	}
}
EOF

# config.yml file
RANDOM_KEY=$(openssl rand -hex 32)
cat <<EOF > config.yml
server:
  port: 8888
  mode: debug
secret:
  token: $RANDOM_KEY
db:
  user:
  password:
  host:
  port:
  name:
EOF

# .gitignore
cat <<EOF > .gitignore
**/config.y*ml
**/gen.sh
**/docker-compose.y*ml
**/compose.y*ml
EOF
echo
echo "Setup complete."
