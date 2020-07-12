package main

// Adapted from grpc-ecosystem example at
// 	https://github.com/grpc-ecosystem/grpc-gateway

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"

	adderv1 "github.com/robinbryce/quorum-gcp-preemptible/adder/api/adder/v1"
)

func healthCheck(conn *grpc.ClientConn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		if s := conn.GetState(); s != connectivity.Ready {
			http.Error(w, fmt.Sprintf("adder-http1 server is %s", s), http.StatusBadGateway)
			return
		}
		fmt.Fprintln(w, "ok")
	}
}

func main() {

	endpoint, ok := os.LookupEnv("SERVICE_ENDPOINT")
	if !ok {
		log.Fatalf("SERVICE_ENDPOINT not set")
	}
	port, ok := os.LookupEnv("PORT")
	if !ok {
		log.Fatalf("PORT not set")
	}
	host := fmt.Sprintf("%s:%s", os.Getenv("HOST"), port)

	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	conn, err := grpc.DialContext(ctx, endpoint, grpc.WithInsecure())
	if err != nil {
		log.Fatalf("dialling `%s': %v", endpoint, err)
	}
	go func() {
		<-ctx.Done()
		if err := conn.Close(); err != nil {
			log.Printf("failed to close a client connection to adder: %v", err)
		}
	}()

	// Register the health check and gRPC server endpoint
	gw := runtime.NewServeMux()
	err = adderv1.RegisterAdderHandler(ctx, gw, conn)
	if err != nil {
		log.Fatalf("registering handler: %v", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthCheck(conn))
	mux.Handle("/", gw)

	// Start HTTP server (and proxy calls to gRPC server endpoint)
	err = http.ListenAndServe(host, mux)
	if err != nil {
		log.Fatalf("ListenAndServe: %v", err)
	}
}
