module github.com/robinbryce/quorum-gcp-preemptible/adder

go 1.13

replace github.com/ethereum/go-ethereum => github.com/jpmorganchase/quorum v2.6.0+incompatible

// We also need to be very picky about the goleveldb version for quorum's
// benefit. The go modules minimum version selection is missing the
// "DisableSeekCompaction" option
replace github.com/syndtr/goleveldb => github.com/syndtr/goleveldb v1.0.1-0.20190923125748-758128399b1d

require (
	github.com/allegro/bigcache v1.2.1 // indirect
	github.com/aristanetworks/goarista v0.0.0-20200609010056-95bcf8053598 // indirect
	github.com/deckarep/golang-set v1.7.1 // indirect
	github.com/edsrzf/mmap-go v1.0.0 // indirect
	github.com/elastic/gosigar v0.10.5 // indirect
	github.com/ethereum/go-ethereum v0.0.0-00010101000000-000000000000
	github.com/fjl/memsize v0.0.0-20190710130421-bcb5799ab5e5 // indirect
	github.com/gballet/go-libpcsclite v0.0.0-20191108122812-4678299bea08 // indirect
	github.com/golang/protobuf v1.4.2
	github.com/gorilla/websocket v1.4.2 // indirect
	github.com/grpc-ecosystem/go-grpc-middleware v1.2.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway v1.14.6
	github.com/hashicorp/go-hclog v0.14.1 // indirect
	github.com/hashicorp/go-plugin v1.3.0 // indirect
	github.com/hashicorp/golang-lru v0.5.4 // indirect
	github.com/huin/goupnp v1.0.0 // indirect
	github.com/jackpal/go-nat-pmp v1.0.2 // indirect
	github.com/jpmorganchase/quorum-hello-world-plugin-sdk-go v0.0.0-20200210211148-57f99f69eeb3 // indirect
	github.com/karalabe/usb v0.0.0-20191104083709-911d15fe12a9 // indirect
	github.com/mattn/go-colorable v0.1.7 // indirect
	github.com/naoina/go-stringutil v0.1.0 // indirect
	github.com/naoina/toml v0.1.1 // indirect
	github.com/olekukonko/tablewriter v0.0.4 // indirect
	github.com/patrickmn/go-cache v2.1.0+incompatible // indirect
	github.com/pborman/uuid v1.2.0 // indirect
	github.com/prometheus/tsdb v0.10.0 // indirect
	github.com/rjeczalik/notify v0.9.2 // indirect
	github.com/rs/cors v1.7.0 // indirect
	github.com/status-im/keycard-go v0.0.0-20200402102358-957c09536969 // indirect
	github.com/steakknife/bloomfilter v0.0.0-20180922174646-6819c0d2a570 // indirect
	github.com/steakknife/hamming v0.0.0-20180906055917-c99c65617cd3 // indirect
	github.com/syndtr/goleveldb v0.0.0-00010101000000-000000000000 // indirect
	github.com/tv42/httpunix v0.0.0-20191220191345-2ba4b9c3382c // indirect
	github.com/tyler-smith/go-bip39 v1.0.2 // indirect
	github.com/wsddn/go-ecdh v0.0.0-20161211032359-48726bab9208 // indirect
	google.golang.org/genproto v0.0.0-20200513103714-09dca8ec2884
	google.golang.org/grpc v1.29.1
	gopkg.in/karalabe/cookiejar.v2 v2.0.0-20150724131613-8dcd6a7f4951 // indirect
	gopkg.in/olebedev/go-duktape.v3 v3.0.0-20200619000410-60c24ae608a6 // indirect
	gopkg.in/urfave/cli.v1 v1.20.0 // indirect
)
