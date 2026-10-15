package cmd

import (
	"crypto/rand"
	"encoding/hex"
	"net"
	"time"
)

type relayAuthState struct {
	RelayID		string 	`json:"relay_id"`
	RelayToken	string	`json:"relay_token"`
}

type commandSpec struct {
	name	string
	method	string
	flagKeys []string
	boolFlags []string
	isParams	bool
	paramKeyOverrides 	map[string]string
	defaultParams map[string]any
	positionKey	string
	repeatKeys 	[]string
}

type browserCommandSpec struct {
	method                string
	flagKeys              []string
	allowPositionalURL    bool
	allowPositionalScript bool
	allowPositionalKey    bool
	allowPositionalQuery  bool
	allowPositionalValue  bool
	useWorkspaceEnv       bool
	useSurfaceEnv         bool
}

func dialSocketUntil(addr string, refreshAddr func() string, deadline time.Time) (net.Conn, error) {
	//TODO
}

func dialSocket(addr string, refreshAddr func() string) (net.Conn, error) {
	return dialSocketUntil(addr, refreshAddr, time.Time{})
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func init() {
	for i := range commands {
		ov, ok := commandOverrides[commands[i].name]
		if !ok {
			continue
		}

		if ov.paramKeyOverrides != nil {
			commands[i].paramKeyOverrides = ov.paramKeyOverrides
		}
	}
}
