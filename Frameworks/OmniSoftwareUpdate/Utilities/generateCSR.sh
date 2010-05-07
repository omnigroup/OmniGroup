#!/bin/zsh
#
# $Id$
#

#
# This generates a CSR using OpenSSL. Unfortunately it's not possible to generate a CSR with the correct attributes using Apple's X.509 CSR passthrough.
#

# Parameters.
DSA_BITS=1024
REQ_DN='/OU=Automatic Software Update/O=Omni Development, Inc./L=Seattle/ST=Washington/C=US/'

if [ -z "$OPENSSL_CONF" ]; then
    if [ -s ./osu-openssl.conf ]; then
        export OPENSSL_CONF=`pwd`/osu-openssl.conf
    fi
fi

echo 'Enter CN of the cert, or hit return to use default'
IFS= read -r 'CommonName'

if [ -z "$CommonName" ]; then
    CommonName='Appcast Feed'
fi
subj='/CN='"$CommonName$REQ_DN"

echo "Using:"
echo "  OpenSSL config file: $OPENSSL_CONF"
echo "  Subject name: $subj"
echo
echo

DESTDIR=`mktemp -d ./gencsr_XXX` || exit 1

export CADIR=/

openssl dsaparam -outform PEM -genkey $DSA_BITS > "$DESTDIR/privkey.pem" || exit 1
openssl req -verbose -new -key "$DESTDIR/privkey.pem" -subj "$subj" -reqexts osu_extensions -outform PEM -text -out "$DESTDIR/csr.pem"

echo
echo
echo "Output is in $DESTDIR"
ls -l "$DESTDIR"

echo
echo "Send the CSR file to the CA for signing, and then install this private key and the returned certificate in the appropriate keychain."
