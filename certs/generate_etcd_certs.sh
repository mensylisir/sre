#!/bin/bash

set -e
set -o pipefail

HOSTNAMES=("etcd1" "etcd2" "etcd3")
IPS=("10.5.114.221" "10.5.114.222" "10.5.114.223")
MASTER_HOSTNAMES=("master1", "master2", "master3")
MASTER_IPS=("10.5.109.1", "10.9.109.2", "10.9.109.3")
FIRST_ETCD_HOSTNAME=${HOSTNAMES[0]}
echo "================================================="
echo "Generating certificates for the following hosts and IPs:"
echo "Hostnames: ${HOSTNAMES[*]}"
echo "IP Addresses: ${IPS[*]}"
echo "================================================="
echo

echo "--> Generating CA certificate and private key..."
if [ ! -f "ca-key.pem" ]; then
    openssl genrsa -out ca-key.pem 2048
    openssl req -new -x509 -sha256 \
        -days 36500 \
        -key ca-key.pem \
        -out ca.pem \
        -subj "/CN=etcd-ca"
    echo "CA generated: ca.pem, ca-key.pem"
else
    echo "CA files already exist, skipping generation."
fi
echo

for i in "${!HOSTNAMES[@]}"; do
    hostname="${HOSTNAMES[$i]}"

    echo "--> Generating certificates for node ${hostname}..."

    cat > "openssl-${hostname}.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = ${hostname}
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF

    dns_count=2
    for name in "${HOSTNAMES[@]}"; do
        echo "DNS.${dns_count} = ${name}" >> "openssl-${hostname}.cnf"
        dns_count=$((dns_count + 1))
    done

    for name in "${MASTER_HOSTNAMES[@]}"; do
        echo "DNS.${dns_count} = ${name}" >> "openssl-${hostname}.cnf"
        dns_count=$((dns_count + 1))
    done

    ip_count=2
    for ip in "${IPS[@]}"; do
        echo "IP.${ip_count} = ${ip}" >> "openssl-${hostname}.cnf"
        ip_count=$((ip_count + 1))
    done

    for ip in "${MASTER_IPS[@]}"; do
        echo "IP.${ip_count} = ${ip}" >> "openssl-${hostname}.cnf"
        ip_count=$((ip_count + 1))
    done

    echo "    - Generating member-${hostname} certificate..."
    openssl genrsa -out "member-${hostname}-key.pem" 2048

    openssl req -new -sha256 \
        -key "member-${hostname}-key.pem" \
        -out "member-${hostname}.csr" \
        -subj "/CN=${hostname}"

    openssl x509 -req -sha256 \
        -days 36500 \
        -in "member-${hostname}.csr" \
        -CA ca.pem \
        -CAkey ca-key.pem \
        -CAcreateserial \
        -out "member-${hostname}.pem" \
        -extfile "openssl-${hostname}.cnf" \
        -extensions v3_req

    echo "    - Generating admin-${hostname} certificate..."
    cp "member-${hostname}-key.pem" "admin-${hostname}-key.pem"
    cp "member-${hostname}.pem" "admin-${hostname}.pem"
    echo "Certificates for node ${hostname} generated."
    echo
done
for i in "${!MASTER_HOSTNAMES[@]}"; do
  hostname="${MASTER_HOSTNAMES[$i]}"
  cp "member-${FIRST_ETCD_HOSTNAME}-key.pem" "admin-${hostname}-key.pem"
  cp "member-${FIRST_ETCD_HOSTNAME}.pem" "admin-${hostname}.pem"
done


echo "--> Cleaning up temporary files (*.csr, *.cnf, *.srl)..."
rm -f ./*.csr ./*.cnf ./*.srl
echo

echo "================================================="
echo "All certificates have been generated. Final file list:"
ls -l *.pem
echo "================================================="
echo
echo "Next step: Distribute the corresponding certificate files to /etc/ssl/etcd/ssl/ on each node."
echo "For example, copy the following files to the etcd1 node:"
echo "  - ca.pem"
echo "  - member-etcd1.pem"
echo "  - member-etcd1-key.pem"
echo "(The admin certificates are for etcdctl or other clients)"
