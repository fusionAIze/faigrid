#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Internal CA & TLS Generator
# ==============================================================================
# This script generates a local Certificate Authority (CA) and issues self-signed 
# TLS certificates for the `grid-core` and `grid-worker` networks, ensuring 
# all traffic between the Edge proxy and internal services is fully encrypted.

set -euo pipefail

DEST_DIR="/opt/fusionaize-nexus/certs"
mkdir -p "$DEST_DIR"

if command -v mkcert > /dev/null 2>&1; then
    echo "[INFO] mkcert found. Generating internal LAN certificates..."
    cd "$DEST_DIR" || exit
    mkcert -install
    mkcert -cert-file grid-core.pem -key-file grid-core-key.pem "grid-core.local" "localhost" "127.0.0.1" "::1"
    echo "[SUCCESS] Internal TLS certificates generated via mkcert in ${DEST_DIR}"
else
    echo "[INFO] mkcert not found. Falling back to native OpenSSL self-signed generation..."
    
    cd "$DEST_DIR" || exit
    
    # Generate CA
    openssl genrsa -out nexus-ca.key 4096 2>/dev/null
    openssl req -x509 -new -nodes -key nexus-ca.key -sha256 -days 3650 -out nexus-ca.crt \
        -subj "/C=XX/ST=Local/L=Local/O=fusionAIze Grid/OU=Internal/CN=fusionAIze Grid Local CA" 2>/dev/null
    
    # Generate Server Cert
    openssl genrsa -out grid-core.key 2048 2>/dev/null
    openssl req -new -key grid-core.key -out grid-core.csr \
        -subj "/C=XX/ST=Local/L=Local/O=fusionAIze Grid/OU=Internal/CN=grid-core.local" 2>/dev/null
        
    # Sign Server Cert
    cat > extfile.cnf << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = grid-core.local
IP.1 = 127.0.0.1
IP.2 = 10.0.0.100
EOF

    openssl x509 -req -in grid-core.csr -CA nexus-ca.crt -CAkey nexus-ca.key \
        -CAcreateserial -out grid-core.crt -days 3650 -sha256 -extfile extfile.cnf 2>/dev/null
    
    # Cleanup
    rm grid-core.csr extfile.cnf
    
    echo "[SUCCESS] Internal TLS certificates generated via OpenSSL in ${DEST_DIR}"
fi
