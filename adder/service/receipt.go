package main

import (
	"context"
	"log"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

const (
	receiptTimeout = 15 * time.Second
)

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
