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

	adderv1 "github.com/robinbryce/quorum-gcp-preemptible/adder/api/adder/v1"
)

func main() {

	port, ok := os.LookupEnv("PORT")
	if !ok {
		log.Fatalf("PORT not set")
	}
	endpoint := fmt.Sprintf("%s:%s", os.Getenv("HOST"), port)

	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Register gRPC server endpoint
	// Note: Make sure the gRPC server is running properly and accessible
	mux := runtime.NewServeMux()
	opts := []grpc.DialOption{grpc.WithInsecure()}
	err := adderv1.RegisterAdderHandlerFromEndpoint(ctx, mux, endpoint, opts)
	if err != nil {
		log.Fatalf("registering handler: %v", err)
	}

	// Start HTTP server (and proxy calls to gRPC server endpoint)
	err = http.ListenAndServe(endpoint, mux)
	if err != nil {
		log.Fatalf("ListenAndServe: %v", err)
	}
}
