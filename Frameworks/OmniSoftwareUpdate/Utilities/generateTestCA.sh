#!/bin/sh
#
# $Id$
#

export CADIR=`pwd`/ca
export OPENSSL_CONF=`pwd`/osu-openssl.conf
dn='/OU=Automatic Software Update/O=Omni Development, Inc./L=Seattle/ST=Washington/C=US/'

keyring=/Volumes/Local/wiml/Products/Debug/sigtest.keychain

if [ ! -d ca ]; then
  mkdir ca || exit 1

  echo "01" > ca/serial
  true > ca/index.txt

  mkdir ca/certs
  mkdir ca/newcerts
  mkdir ca/private

  openssl genrsa -out ca/private/ca-tmp.pem 2048
  openssl pkcs8 -topk8 -in ca/private/ca-tmp.pem -out ca/private/ca.pem -nocrypt -outform PEM
  rm ca/private/ca-tmp.pem

  openssl req -new -x509 -extensions osu_ca_extensions -subj "/CN=[TEST] Omni Development Software Distribution CA$dn" -key ca/private/ca.pem -text -outform PEM -out ca/certs/cacert.pem
  
  openssl dsaparam 1024 -text -out ca/dsaparam-1024.pem
  openssl dsaparam 2048 -text -out ca/dsaparam-2048.pem
fi


if [ ! -f ca/private/dsakey1024.pem ]; then
  openssl gendsa -out ca/private/dsakey1024.pem ca/dsaparam-1024.pem && \
  openssl req -new -key ca/private/dsakey1024.pem -subj '/CN=Test Key DSA-1024'"$dn" -out ca/newcerts/dsa1024.req && \
  openssl ca -verbose -name omnisoftwareupdate -days 30 -in ca/newcerts/dsa1024.req -out ca/newcerts/dsa1024.pem && \
  rm ca/newcerts/dsa1024.req
fi

if [ ! -f ca/private/dsakey2048.pem ]; then
  openssl gendsa -out ca/private/dsakey2048.pem ca/dsaparam-2048.pem && \
  openssl req -new -key ca/private/dsakey2048.pem -subj '/CN=Test Key DSA-2048'"$dn" -out ca/newcerts/dsa2048.req && \
  openssl ca -verbose -name omnisoftwareupdate -days 30 -in ca/newcerts/dsa2048.req -out ca/newcerts/dsa2048.pem && \
  rm ca/newcerts/dsa2048.req
fi

if [ ! -f ca/private/ecdsakey.pem ]; then
  openssl ecparam -name sect571r1 -text -genkey -out ca/private/ecdsakey.pem && \
  openssl pkcs8 -topk8 -in ca/private/ecdsakey.pem -out ca/private/ecdsakey-pk8.pem -nocrypt -outform PEM && \
  openssl req -new -key ca/private/ecdsakey.pem -subj '/CN=Test Key EllipticDSA'"$dn" -out ca/newcerts/ecdsa.req && \
  openssl ca -verbose -name omnisoftwareupdate -days 30 -in ca/newcerts/ecdsa.req -out ca/newcerts/ecdsa.pem && \
  rm ca/newcerts/ecdsa.req
fi

if [ -f "$keyring" ]; then
  for f in ca/certs/cacert.pem ca/newcerts/*.pem
  do
    security import "$f" -k "$keyring" -t cert -f openssl
  done
  
  for f in ca/private/*.pem 
  do
    security import "$f" -k "$keyring" -t priv
  done
fi

