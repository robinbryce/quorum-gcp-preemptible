package main

// Adapted from helloworld example described here
// 	https://grpc.io/docs/languages/go/quickstart/

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"io/ioutil"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	"google.golang.org/grpc/health/grpc_health_v1"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"

	"github.com/ethereum/go-ethereum/rpc"
	"github.com/robinbryce/quorum-gcp-preemptible/adder/adder"
	v1adder "github.com/robinbryce/quorum-gcp-preemptible/adder/api/adder/v1"
)

const (
	// Quorum Specific GasLimit strategy: It is critical that this amount is
	// less than the target floor for the block gas limit. Which defaults to
	// 700,000,000 and is set by the --miner.gastarget cli switch for geth. We
	// also want it as big as possible so as to never have to worry about gas.
	transactionGasLimit = 500000000
	receiptTimeout      = 15 * time.Second
	ethRPCTimeout       = 5 * time.Second
)

type adderService struct {
	v1adder.UnimplementedAdderServer
	auth      *bind.TransactOpts
	ethc      *ethclient.Client
	adderAddr common.Address
	adder     *adder.Adder
}

func responseFromTransaction(tx *types.Transaction) *v1adder.TransactionResponse {

	log.Printf("tx: %v", tx)
	if tx == nil {
		return nil
	}
	tr := &v1adder.TransactionResponse{
		Data: &v1adder.Transaction{},
	}
	tr.Data.Nonce = tx.Nonce()
	tr.Data.GasPrice = tx.GasPrice().Bytes()
	to := tx.To()
	if to != nil {
		tr.Data.To = to.Hex()
	}
	tr.Data.Value = tx.Value().Bytes()
	tr.Data.Payload = tx.Data()

	v, r, s := tx.RawSignatureValues()

	tr.Data.V = v.Bytes()
	tr.Data.R = r.Bytes()
	tr.Data.S = s.Bytes()

	tr.Hash = tx.Hash().Hex()
	return tr
}

func (a *adderService) Set(
	ctx context.Context, req *v1adder.SetRequest) (*v1adder.TransactionResponse, error) {

	v := big.NewInt(0).SetUint64(req.Value)
	log.Printf("setting: %v, %v", req, v)

	tx, err := a.adder.Set(a.auth, v)
	if err != nil {
		return nil, status.Errorf(codes.Unknown, "set: %v", err)
	}

	return responseFromTransaction(tx), nil
}

func (a *adderService) Get(
	ctx context.Context, req *v1adder.GetRequest) (*v1adder.GetResponse, error) {

	v, err := a.adder.Get(nil)
	if err != nil {
		return nil, status.Errorf(codes.Unknown, "get: %v", err)
	}
	return &v1adder.GetResponse{Value: v.Uint64()}, nil
}

func (a *adderService) Add(
	ctx context.Context, req *v1adder.AddRequest) (*v1adder.TransactionResponse, error) {

	v := big.NewInt(0).SetUint64(req.Value)
	log.Printf("adding: %v, %v", req, v)

	tx, err := a.adder.Add(a.auth, v)
	if err != nil {
		return nil, status.Errorf(codes.Unknown, "add: %v", err)
	}

	return responseFromTransaction(tx), nil
}

func newTransactor(key *ecdsa.PrivateKey) *bind.TransactOpts {
	auth := bind.NewKeyedTransactor(key)

	auth.Value = big.NewInt(0)                  // in wei
	auth.GasLimit = uint64(transactionGasLimit) // in units
	return auth
}

func (a *adderService) Check(
	ctx context.Context, req *grpc_health_v1.HealthCheckRequest,
) (*grpc_health_v1.HealthCheckResponse, error) {
	log.Println("health check")
	return &grpc_health_v1.HealthCheckResponse{
		Status: grpc_health_v1.HealthCheckResponse_SERVING,
	}, nil
}

func (a *adderService) Watch(
	req *grpc_health_v1.HealthCheckRequest, w grpc_health_v1.Health_WatchServer) error {
	return status.Error(codes.Unimplemented, "Watching is not supported")
}

func main() {

	var err error
	log.Printf("starting")

	listenPort := os.Getenv("PORT")
	ethAddressRPC, ok := os.LookupEnv("ETH_RPC")
	if !ok {
		log.Fatalf("ETH_RPC not provided")
	}

	deployedAddress, deployed := os.LookupEnv("CONTRACT_ADDRESS")

	// Note: we use this key for contract deployment. This means it needs to be
	// funded well enough to cover the *estimated* deployment gas cost. The
	// cost is not deducted from the wallet, but the funds are required.
	walletKeyFile, ok := os.LookupEnv("WALLET_KEY")
	if !ok {
		log.Fatalf("WALLET_KEY not provided")
	}

	log.Printf("PORT: %s, ETH_RPC: %s, WALLET_KEY: %s",
		listenPort, ethAddressRPC, walletKeyFile)

	server := grpc.NewServer()

	a := &adderService{}

	v1adder.RegisterAdderServer(server, a)
	grpc_health_v1.RegisterHealthServer(server, a)
	reflection.Register(server)

	// Load our private key
	var walletKey *ecdsa.PrivateKey
	var rawKey []byte
	if rawKey, err = ioutil.ReadFile(walletKeyFile); err != nil {
		log.Fatalf("failed to read key, `%s`: %v", walletKeyFile, err)
	}

	if walletKey, err = crypto.ToECDSA(rawKey); err != nil {
		log.Fatalf("failed to decode key, `%s`: %v", hex.Dump(rawKey), err)
	}
	a.auth = newTransactor(walletKey)

	var rpcc *rpc.Client
	if rpcc, err = rpc.DialHTTPWithClient(
		ethAddressRPC, &http.Client{Timeout: 30 * time.Second}); err != nil {
		log.Fatalf("failed dialing `%s'", ethAddressRPC)
	}
	a.ethc = ethclient.NewClient(rpcc)

	if !deployed {

		// Deploy the contract. We do this un-conditionaly everytime the services
		// starts.
		var tx *types.Transaction
		if a.adderAddr, tx, a.adder, err = adder.DeployAdder(a.auth, a.ethc); err != nil {
			log.Fatalf("deploying contract: %v", err)
		}
		_ = a.receiptOrFatal(tx, "deploying contract: ")
		log.Printf("deployed contract: %s", a.adderAddr.Hex())

	} else {

		a.adderAddr = common.HexToAddress(deployedAddress)
		// Check the code at CONTRACT_ADDRESS matches the runtime code
		// compiled in to the service binary.
		ctx, cancel := context.WithTimeout(context.Background(), ethRPCTimeout)
		defer cancel()
		var code []byte
		code, err = a.ethc.CodeAt(ctx, a.adderAddr, nil)
		if err != nil {
			log.Fatalf("error checking contract code at `%s': %v", deployedAddress, err)
		}
		if len(code) == 0 {
			log.Fatalf("0 length contract code at `%s'", deployedAddress)
		}

		if !bytes.Equal(code, common.FromHex(adder.BinRuntime)) {

			log.Fatalf(
				"contract code at `%s' does not match service contract", deployedAddress)
		}
		log.Printf("matched code at `%s'", deployedAddress)

		a.adder, err = adder.NewAdder(a.adderAddr, a.ethc)
		if err != nil {
			log.Fatalf("error binding contract code at `%s': %v", deployedAddress, err)
		}
	}

	// Note that at no point do we import / unlock or otherwise rely on geth
	// for account management.

	listen, err := net.Listen("tcp", ":"+listenPort)
	if err != nil {
		log.Fatalf("startup error: %v", err)
	}

	log.Printf("adder server starting")
	err = server.Serve(listen)
	if err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}

func (a *adderService) receiptOrFatal(tx *types.Transaction, fatalmsg string) *types.Receipt {
	var err error
	var r *types.Receipt
	var attempt int
	for {
		time.Sleep(DefaultBackoff.Duration(attempt))
		if r, err = receiptWithTimeout(tx, a.ethc); err != nil {
			attempt++
			continue
		}
		if r == nil {
			log.Fatalf("%sno receipt and no error", fatalmsg)
		}
		if r.Status != 1 {
			log.Fatalf("%sstatus != 1 for %s", fatalmsg, tx.Hash().Hex())
		}
		return r
	}
}

type ReceiptCollector interface {
	TransactionReceipt(ctx context.Context, txHash common.Hash) (*types.Receipt, error)
}

func receiptWithTimeout(tx *types.Transaction, collector ReceiptCollector) (*types.Receipt, error) {
	var err error
	var r *types.Receipt
	ctx, cancel := context.WithTimeout(context.Background(), receiptTimeout)
	defer cancel()
	if r, err = collector.TransactionReceipt(ctx, tx.Hash()); err != nil {
		return nil, err
	}
	return r, nil
}
