#!/bin/bash
set -e

CLOUD_VPS_INSTANCE="wikibase-product-testing-2022.wikidata-dev.eqiad1.wikimedia.cloud";
if [ $(hostname -f) != "$CLOUD_VPS_INSTANCE" ] ; then
    echo "This script must only be run at $CLOUD_VPS_INSTANCE Wikimedia Cloud VPS instance.";
    exit 1;
fi

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z "$IMAGE_PREFIX" ] ; then
    IMAGE_PREFIX=""
fi

if [ -z "$TEST_SYSTEM" ] ; then
    echo "Variable \$TEST_SYSTEM is required but is not set.";
    exit 1;
fi

if [ -z "$BUILD_NUMBER" ] ; then
    echo "Variable \$BUILD_NUMBER is required but is not set.";
    exit 1;
fi

if [ -z "$EXAMPLE_HASH" ] ; then
    echo "Variable \$EXAMPLE_HASH is required but is not set.";
    exit 1;
fi


# Calculate ports and domains
PORT_BASE="83"
DOMAIN_SUFFIX=-$TEST_SYSTEM
if [ "$TEST_SYSTEM" == "previous" ];
then
    PORT_BASE="82"
fi
if [ "$TEST_SYSTEM" == "latest" ];
then
    # Do not suffix domains on the latest system
    DOMAIN_SUFFIX=""
    PORT_BASE="83"
fi
if [ "$TEST_SYSTEM" == "fedprops-previous" ];
then
    PORT_BASE="84"
fi
if [ "$TEST_SYSTEM" == "fedprops" ];
then
    PORT_BASE="85"
fi

umask 002
mkdir -p /opt/test-systems/$TEST_SYSTEM
cd /opt/test-systems/$TEST_SYSTEM

# Download the repo at the desired version, and extract the example
wget https://github.com/wmde/wikibase-release-pipeline/archive/$EXAMPLE_HASH.zip
unzip $EXAMPLE_HASH.zip
rm $EXAMPLE_HASH.zip
cp -r ./wikibase-release-pipeline-$EXAMPLE_HASH/example/* .
rm -rf ./wikibase-release-pipeline-$EXAMPLE_HASH

# Create a .env file
cp ./template.env ./.env
echo "# Test system customizations" >> ./.env
# Default settings to change
echo "MW_WG_ENABLE_UPLOADS=true" >> ./.env
# Public facing domains
echo "WIKIBASE_HOST=wikibase-product-testing$DOMAIN_SUFFIX.wmflabs.org" >> ./.env
echo "WDQS_FRONTEND_HOST=wikibase-query-testing$DOMAIN_SUFFIX.wmflabs.org" >> ./.env
echo "QUICKSTATEMENTS_HOST=wikibase-qs-testing$DOMAIN_SUFFIX.wmflabs.org" >> ./.env
# Images to use
echo "WIKIBASE_IMAGE_NAME=${IMAGE_PREFIX}wikibase:$BUILD_NUMBER" >> ./.env
echo "WDQS_IMAGE_NAME=${IMAGE_PREFIX}wdqs:$BUILD_NUMBER" >> ./.env
echo "WDQS_FRONTEND_IMAGE_NAME=${IMAGE_PREFIX}wdqs-frontend:$BUILD_NUMBER" >> ./.env
echo "ELASTICSEARCH_IMAGE_NAME=${IMAGE_PREFIX}elasticsearch:$BUILD_NUMBER" >> ./.env
echo "WIKIBASE_BUNDLE_IMAGE_NAME=${IMAGE_PREFIX}wikibase-bundle:$BUILD_NUMBER" >> ./.env
echo "QUICKSTATEMENTS_IMAGE_NAME=${IMAGE_PREFIX}quickstatements:$BUILD_NUMBER" >> ./.env
echo "WDQS_PROXY_IMAGE_NAME=${IMAGE_PREFIX}wdqs-proxy:$BUILD_NUMBER" >> ./.env
# Ports to expose
echo "WIKIBASE_PORT=${PORT_BASE}80" >> ./.env
echo "WDQS_FRONTEND_PORT=${PORT_BASE}81" >> ./.env
echo "QS_PUBLIC_SCHEME_HOST_AND_PORT=https://wikibase-qs-testing$DOMAIN_SUFFIX.wmcloud.org" >> ./.env
echo "WB_PUBLIC_SCHEME_HOST_AND_PORT=https://wikibase-product-testing$DOMAIN_SUFFIX.wmcloud.org" >> ./.env
echo "QUICKSTATEMENTS_PORT=${PORT_BASE}82" >> ./.env

# Modify the quickstatements WB_PUBLIC_SCHEME_HOST_AND_PORT in the example
# TODO if this works for the test system, push this to the real example...
sed -i 's/WB_PUBLIC_SCHEME_HOST_AND_PORT=http:\/\/${WIKIBASE_HOST}:${WIKIBASE_PORT}/WB_PUBLIC_SCHEME_HOST_AND_PORT=${WB_PUBLIC_SCHEME_HOST_AND_PORT}/' ./docker-compose.extra.yml

# Create an extra LocalSettings.php file to load
cp $SCRIPT_DIR/extra-localsettings.txt ./extra.LocalSettings.php
sed -i 's/#- .\/LocalSettings.php:\/var\/www\/html\/LocalSettings.d\/LocalSettings.override.php/- .\/extra.LocalSettings.php:\/var\/www\/html\/LocalSettings.d\/LocalSettings.extra.php/' ./docker-compose.yml

if [[ "$TEST_SYSTEM" == *"fedprop"* ]]; then
  echo "Configuring federated properties"
  cp $SCRIPT_DIR/extra-localsettings-fedprops.txt >> ./extra.LocalSettings.php
fi
