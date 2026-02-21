package endpoints

import (
	"embed"
	"fmt"
	"net/http"

	"github.com/julienschmidt/httprouter"
)

//go:embed static/index.html
var staticFiles embed.FS

// NewIndexHandler returns the default '/' route handle function.
// It serves the embedded HTML page if available, falling back to the config message.
func NewIndexHandler(message string) func(http.ResponseWriter, *http.Request, httprouter.Params) {
	htmlContent, err := staticFiles.ReadFile("static/index.html")
	if err != nil {
		// Fall back to plain text config message
		return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
			w.WriteHeader(http.StatusOK)
			fmt.Fprintf(w, message)
		}
	}

	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		w.Write(htmlContent)
	}
}
