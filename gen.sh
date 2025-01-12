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
mkdir -p configs internal/{domains,services,handlers,repositories} pkgs/{errs,logs,utils} server/{middlewares,routes}
# Create files and add content
echo "Creating and populating files..."
# main.go
cat <<EOF > main.go
package main

import (
	"$PROJECT_NAME/configs"
	"$PROJECT_NAME/pkgs/logs"
	"$PROJECT_NAME/server/routes"
	"fmt"
	"log"
	"os"
	"os/signal"

	"github.com/gofiber/fiber/v2"
	"github.com/spf13/viper"
)

var addr string

func init() {
	configs.InitConfigLoader()
	configs.InitTimeZone()
	logs.LogInit()
}

func main() {
	app := fiber.New(fiber.Config{
		AppName: "$PROJECT_NAME",
	})

	routes.RegisterRoutes(app)

	// Gracefully shutting down
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	go func() {
		serv := <-c
		if serv.String() == "interrupt" {
			fmt.Println("\nGracefully shutting down...")
			app.Shutdown()
		}
	}()

	if viper.GetString("server.mode") == "debug" {
		addr = "localhost:" + viper.GetString("server.port")
	} else {
		addr = ":" + viper.GetString("server.port")
	}

	if err := app.Listen(addr); err != nil {
		log.Fatal(err)
	}
}
EOF

# routes.go
cat <<EOF > server/routes/routes.go
package routes

import "github.com/gofiber/fiber/v2"

func RegisterRoutes(app *fiber.App) {
	// Grouping router
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

func InitConfigLoader() {
	viper.SetConfigName("config")
	viper.SetConfigType("yml")
	viper.AddConfigPath(".")
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	viper.ReadInConfig()
}

func InitTimeZone() {
	ict, err := time.LoadLocation("Asia/Bangkok")
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
	time.Local = ict
}
EOF

# internal/handlers/utils.go
cat <<EOF > internal/handlers/utils.go
package handlers

import (
	"$PROJECT_NAME/pkgs/errs"
	"fmt"

	"github.com/gofiber/fiber/v2"
)

func handleError(c *fiber.Ctx, err error) error {
	switch e := err.(type) {
	case errs.AppError:
		fmt.Fprintln(c, e)
		return c.SendStatus(e.Code)
	case error:
		fmt.Fprintln(c, e)
		return c.SendStatus(fiber.StatusInternalServerError)
	}
	return nil
}
EOF

# internal/services/utils.go
cat <<EOF > internal/services/utils.go
package services

import (
	"fmt"
	"reflect"
)

func mapStructFields(src interface{}, dest interface{}) error {
	srcValue := reflect.ValueOf(src)
	destValue := reflect.ValueOf(dest)

	// Ensure src is a struct and dest is a pointer to a struct
	if srcValue.Kind() != reflect.Struct {
		return fmt.Errorf("source must be a struct")
	}
	if destValue.Kind() != reflect.Ptr || destValue.Elem().Kind() != reflect.Struct {
		return fmt.Errorf("destination must be a pointer to a struct")
	}

	destElem := destValue.Elem()

	// Iterate over source fields
	for i := 0; i < srcValue.NumField(); i++ {
		srcField := srcValue.Type().Field(i) // Get the field metadata
		srcFieldName := srcField.Name
		srcFieldValue := srcValue.Field(i)

		// Find matching field in the destination
		destField := destElem.FieldByName(srcFieldName)
		if destField.IsValid() && destField.CanSet() && destField.Type() == srcFieldValue.Type() {
			destField.Set(srcFieldValue)
		}
	}
	return nil
}
EOF

# logger.go
LOG_FORMAT="[\${time}] | \${status} | \${latency} | \${ip} | \${method} | \${path} | \${error}\\n"

cat <<EOF > server/middlewares/log.go
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
cat <<EOF > server/middlewares/cors.go
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
cat <<EOF > pkgs/logs/logs.go
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
cat <<EOF > pkgs/errs/errs.go
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

# pkgs/utils/builder.go
cat <<EOF > pkgs/utils/builder.go
package utils

import (
	"fmt"

	"github.com/spf13/viper"
)

func URLBuilder(connType string) string {
	switch connType {
	case "server":
		addr := ""
		if viper.GetString("server.mode") == "debug" {
			addr = "localhost:" + viper.GetString("server.port")
		} else {
			addr = ":" + viper.GetString("server.port")
		}
		return addr

	case "postgres":
		return fmt.Sprintf(
			"host=%v user=%v password=%v dbname=%v port=%v sslmode=disable TimeZone=Asia/Bangkok",
			viper.GetString("db.host"),
			viper.GetString("db.user"),
			viper.GetString("db.password"),
			viper.GetString("db.name"),
			viper.GetInt("db.port"),
		)

	case "mysql":
		return fmt.Sprintf(
			"%v:%v@tcp(%v:%v)/%v?charset=utf8&parseTime=True",
			viper.GetString("db.username"),
			viper.GetString("db.password"),
			viper.GetString("db.host"),
			viper.GetInt("db.port"),
			viper.GetString("db.dbname"),
		)
	default:
		return ""
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
