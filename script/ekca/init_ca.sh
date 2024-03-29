#!/usr/bin/env bash

#set -x

#set -euf
OS=$(uname)
DATE_FMT_BEFORE=""
DATE_FMT_AFTER=""
SED_CMD=""

if [ "$OS" == "Linux" ]; then
    DATE_FMT_BEFORE="+%y%m%d000000Z -u -d -1day"
    DATE_FMT_AFTER="+%y%m%d000000Z -u -d +10years+1day"
    SED_CMD="sed -i"
elif [ "$OS" == "FreeBSD" ]; then
    DATE_FMT_BEFORE="-u -v-1d +%y%m%d000000Z"
    DATE_FMT_AFTER="-u -v+10y +%y%m%d000000Z"
    SED_CMD="sed -i '' -e"
fi

EKCADIR="$(dirname $(realpath ${0}))/"
CA_DIR="${1-.}/ca"

if test -e $CA_DIR; then
    exit
fi
mkdir -p $CA_DIR
echo "CA build in \"$CA_DIR\" realpath: \"$(realpath $CA_DIR)\"" 1>&2

pushd "$CA_DIR"

mkdir root-ca
pushd root-ca

mkdir certreqs certs crl newcerts private
touch root-ca.index
echo 00 > root-ca.crlnum
echo 1000 > root-ca.serial
echo "123456" > pass.txt

cp "${EKCADIR}/root-ca.cnf" ./
export OPENSSL_CONF=./root-ca.cnf
ROOT_URL="file:$ROOTCRT"
${SED_CMD} "s|ROOTCRT|$ROOT_URL|g" $OPENSSL_CONF
ROOT_URL="file:$ROOTCRL"
${SED_CMD} "s|ROOTCRL|$ROOT_URL|g" $OPENSSL_CONF
openssl req -new -out root-ca.req.pem -passout file:pass.txt

#
# Create self signed root certificate
#

openssl ca -selfsign \
    -in root-ca.req.pem \
    -out root-ca.cert.pem \
    -extensions root-ca_ext \
    -startdate `date ${DATE_FMT_BEFORE}` \
    -enddate `date ${DATE_FMT_AFTER}` \
    -passin file:pass.txt -batch

openssl x509 -outform der -in  root-ca.cert.pem -out root-ca.cert.crt

openssl verify -verbose -CAfile root-ca.cert.pem \
        root-ca.cert.pem

openssl ca -gencrl  -cert root-ca.cert.pem \
        -out root-ca.cert.crl.pem -passin file:pass.txt
openssl crl -in root-ca.cert.crl.pem -outform DER -out root-ca.cert.crl

popd #root-ca

#
# Create intermediate certificate
#
mkdir intermed-ca
pushd intermed-ca

mkdir certreqs certs crl newcerts private
touch intermed-ca.index
echo 00 > intermed-ca.crlnum
echo 2000 > intermed-ca.serial
echo "123456" > pass.txt

cp "${EKCADIR}/intermed-ca.cnf" ./
export OPENSSL_CONF=./intermed-ca.cnf

# Adapt CRT URL to current test directory
${SED_CMD} "s|ROOTCRT|$ROOT_URL|g" $OPENSSL_CONF

openssl req -new -out intermed-ca.req.pem -passout file:pass.txt

openssl rsa -inform PEM -in private/intermed-ca.key.pem \
        -outform DER -out private/intermed-ca.key.der -passin file:pass.txt

cp intermed-ca.req.pem  \
   ../root-ca/certreqs/

INTERMED_URL="file:$INTERMEDCRT"
${SED_CMD} "s|INTERMEDCRT|$INTERMED_URL|g" $OPENSSL_CONF

pushd ../root-ca
export OPENSSL_CONF=./root-ca.cnf

openssl ca \
    -in certreqs/intermed-ca.req.pem \
    -out certs/intermed-ca.cert.pem \
    -extensions intermed-ca_ext \
    -startdate `date ${DATE_FMT_BEFORE}` \
    -enddate `date ${DATE_FMT_AFTER}` \
    -passin file:pass.txt -batch

openssl x509 -outform der -in certs/intermed-ca.cert.pem \
        -out certs/intermed-ca.cert.crt

openssl verify -verbose -CAfile root-ca.cert.pem \
        certs/intermed-ca.cert.pem

cp certs/intermed-ca.cert.pem \
   ../intermed-ca

cp certs/intermed-ca.cert.crt \
   ../intermed-ca

popd #root-ca

export OPENSSL_CONF=./intermed-ca.cnf
openssl ca -gencrl  -cert ../root-ca/certs/intermed-ca.cert.pem \
        -out intermed-ca.crl.pem -passin file:pass.txt
openssl crl -in intermed-ca.crl.pem -outform DER -out intermed-ca.crl

popd #intermed-ca
sync
