// Local test transport. Uses Go's HTTP/2 implementation; no protocol shim.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"flag"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

func main() {
	dir := flag.String("work", "", "Task-specific certificate and readiness directory")
	backend := flag.String("backend", "", "Loopback HTTP backend")
	listen := flag.String("listen", "127.0.0.1:0", "TLS listen address")
	certificate := flag.String("cert", "", "Reusable localhost certificate")
	privateKey := flag.String("key", "", "Reusable private key; never copied to work/evidence")
	flag.Parse()
	if *dir == "" || *backend == "" {
		log.Fatal("-work and -backend are required")
	}
	if (*certificate == "") != (*privateKey == "") {
		log.Fatal("-cert and -key must be supplied together")
	}
	target, err := url.Parse(*backend)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(*dir, 0700); err != nil {
		log.Fatal(err)
	}
	certPath, keyPath := *certificate, *privateKey
	if certPath == "" {
		certPath, keyPath = filepath.Join(*dir, "localhost.pem"), filepath.Join(*dir, "localhost-key.pem")
		generateIdentity(certPath, keyPath)
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s %s", r.Proto, r.Method, r.URL.RequestURI())
		if r.URL.Path == "/__http2_health" {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]any{"protocol": r.Proto, "http2": r.ProtoMajor == 2})
			return
		}
		w.Header().Set("X-HLS-Test-Protocol", r.Proto)
		proxy.ServeHTTP(w, r)
	})
	socket, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	ready, _ := json.Marshal(map[string]string{
		"url":         "https://localhost:" + strconv.Itoa(socket.Addr().(*net.TCPAddr).Port),
		"certificate": certPath,
	})
	if err := os.WriteFile(filepath.Join(*dir, "ready.json"), ready, 0600); err != nil {
		log.Fatal(err)
	}
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(server.ServeTLS(socket, certPath, keyPath))
}

func generateIdentity(certPath, keyPath string) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		log.Fatal(err)
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		log.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "HLSPlaylist test localhost " + serial.Text(16)},
		NotBefore:    time.Now().Add(-time.Minute), NotAfter: time.Now().Add(24 * time.Hour),
		DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true, IsCA: true,
	}
	cert, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		log.Fatal(err)
	}
	der, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		log.Fatal(err)
	}
	for name, data := range map[string][]byte{
		certPath: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert}),
		keyPath:  pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: der}),
	} {
		if err := os.WriteFile(name, data, 0600); err != nil {
			log.Fatal(err)
		}
	}
}
