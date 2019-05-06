#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$CONFIG_DIR/config.controller"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

## This script access the OpenStack installation trough the dashboard by making
## wget or curl requests (whichever is available).
## It goes in this order:
## 1: retrieve cookie
## 2: use that cookie for authenticating with user/password and get the session id
## 3: use the session id and token for getting the (provider) network id
## 4: similar to step 3 but get the ID of the cirros image
## 5: launch an instance using the data from steps 2,3 and 4

echo "Testing horizon."

IP=$(echo "$NET_IF_1" |awk '{print $2}')
AUTH_URL="http://$IP/horizon/auth/login/"
DOMAIN="default"
REGION="default"
USER=${ADMIN_USER_NAME}
PASSWORD=${ADMIN_PASS}
OUTPUT_DIR="test_horizon_out"
COOKIE_FILE="$OUTPUT_DIR/cookie.txt"
OUTPUT_FILE1="$OUTPUT_DIR/1.get_cookie.html"
OUTPUT_FILE2="$OUTPUT_DIR/2.check_credentials.html"
OUTPUT_FILE3="$OUTPUT_DIR/3.check_net_id.html"
OUTPUT_FILE4="$OUTPUT_DIR/4.check_image_id.html"
OUTPUT_FILE5="$OUTPUT_DIR/5.launch_instance.html"

echo "Clean previous files and clear variables before starting."
rm -f $COOKIE_FILE $OUTPUT_FILE1 $OUTPUT_FILE2 $OUTPUT_FILE3 $OUTPUT_FILE4 \
    $OUTPUT_FILE5

mkdir -p $OUTPUT_DIR

# Ensure wget or curl are installed
echo "Testing availability of wget or curl."
if which wget &> /dev/null ; then
    REQUEST_TOOL="wget"
elif which curl &> /dev/null; then
    REQUEST_TOOL="curl"
else
    echo "ERROR: neither wget nor curl were found. Please install one with:"
    echo " apt -y install wget"
    exit 1
fi

echo "Found $REQUEST_TOOL."

function request_cmd {
    # Usage:
    # request_cmd URL OUT_FILE [POST_DATA] [REFERER]

    URL=$1
    OUTPUT_FILE=$2

    if [[ -v 3 ]];then
        DATA=$3
    fi

    if [[ -v 4 ]];then
        REFERER=$4
    fi

    POST_ARG=""
    REFERER_ARG=""

    if [ "$REQUEST_TOOL" = "wget" ]; then

        if [ -f "$COOKIE_FILE" ];then
            COOKIE_ARG="--load-cookies=$COOKIE_FILE"
        else
            COOKIE_ARG=""
        fi

        if [[ -v DATA ]]; then
            POST_ARG="--post-data=$DATA"
        fi

        if [[ -v REFERER ]]; then
            REFERER_ARG="--referer=$REFERER"
        fi

        #echo "wget --quiet --keep-session-cookies --save-cookies $COOKIE_FILE \
        #     "$COOKIE_ARG" "$POST_ARG" "$REFERER_ARG" \
        #     --output-document=$OUTPUT_FILE $URL"
        #echo
        wget --quiet --keep-session-cookies --save-cookies $COOKIE_FILE \
            $COOKIE_ARG $POST_ARG $REFERER_ARG \
            --output-document="$OUTPUT_FILE" "$URL"

    elif [ "$REQUEST_TOOL" = "curl" ]; then

        [[ -v DATA ]] && POST_ARG="-d $DATA"
        [[ -v REFERER ]] && REFERER_ARG="--referer $REFERER"

        curl -L -c $COOKIE_FILE -b $COOKIE_FILE $POST_ARG --output "$OUTPUT_FILE"\
            $REFERER_ARG -s "$URL"
    fi
}

# Step 1: get the cookie
echo "Retrieving the cookie from $AUTH_URL."
request_cmd "$AUTH_URL" $OUTPUT_FILE1

# The "TOKEN" variable is the "Cross-site request forgery" prevention token
# It prevents man in the middle attacks
TOKEN=$(grep csrftoken $COOKIE_FILE | sed 's/^.*csrftoken\s*//')

# This data is what is going to be passed as the $_POST of the http request
DATA="username=$USER&password=$PASSWORD&domain=$DOMAIN&region=$REGION&csrfmiddlewaretoken=$TOKEN"

# Step 2: check the login credentials and obtains the session ID
echo "Authenticating with the $USER credentials."
request_cmd "$AUTH_URL" $OUTPUT_FILE2 "$DATA"


# Check that "sessionid" appears in the cookie file
# This SESSIONID keeps the session open to avoid sending the user/password
# at every new request
SESSIONID=$(grep sessionid $COOKIE_FILE | sed 's/^.*sessionid\s*//')
if [ -z "$SESSIONID" ]; then
    echo "Error: sessionid not present on file $COOKIE_FILE ...Exiting."
    exit 1
else
    echo "Login successful."
fi

# We need a new token, because it changes after step 2
TOKEN=$(grep csrftoken $COOKIE_FILE | sed 's/^.*csrftoken\s*//')

NET_URL="http://$IP/horizon/project/networks/"
REFERER="http://$IP/horizon/identity/"
DATA="login_region='http://controller:5000/v3'&login_domain=default&\
csrfmiddlewaretoken=$TOKEN&sessionid=$SESSIONID"

# Step 3: Load the page with the networks
echo "Loading the networks tab and parsing the network ID for provider."
request_cmd "$NET_URL" $OUTPUT_FILE3 "$DATA" "$REFERER"

# Parse (provider) network ID
NET_ID=$(grep "provider" $OUTPUT_FILE3 | \
        awk -F"data-object-id=" '{print $2}' | \
        awk -F'"' '{print $2}')

echo "The provider NET_ID is $NET_ID"

#######
# The following part is broken.
# The same DATA section works on the previous requests so either the
# REFERER or the IMG_URL (not likely) have changed since Mitaka

#IMG_URL="http://$IP/horizon/project/images/"
#DATA="login_region='http://controller:5000/v3'&login_domain=default&\
#csrfmiddlewaretoken=$TOKEN&sessionid=$SESSIONID"

## Step 4: Load the page with the available images
#echo "Loading the images tab and parsing the image ID for cirros."
#request_cmd "$IMG_URL" $OUTPUT_FILE4 "$DATA" "$REFERER"
#
## Parse (cirros) image ID
#IMAGE_ID=$(grep "cirros" $OUTPUT_FILE4 | \
#        awk -F"obj_id=" '{print $2}' | \
#        awk -F'"' '{print $1}')
#
#echo "The cirros IMAGE_ID is $IMAGE_ID"
