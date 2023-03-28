#!/bin/bash

# Usage: ./migrate-to-localwp.sh <ssh-user> <ssh-host> <public-path> --ssh-copy-id

assert_command_exists() {
    if ! command -v "$1" > /dev/null; then
        echo "Error: $1 is not installed"
        exit 1
    fi
}

check_ssh() {
    # Assert that public key authentication is set up
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$1" "exit" 2> /dev/null
}

# Create some whitespace
echo ""
echo ""

# Assert all arguments are present
if [ $# -lt 3 ]; then
    echo "Usage: ./migrate-to-localwp.sh <ssh-user> <ssh-host> <public-path> --ssh-copy-id"
    exit 1
fi

# Assert that all required commands are installed
REQUIRED_COMMANDS=(ssh rsync zip echo cut grep mktemp pwd cd)
for COMMAND in "${REQUIRED_COMMANDS[@]}"
do
    assert_command_exists "$COMMAND"
done

# Get the optional --ssh-copy-id flag
if [ "$4" == "--ssh-copy-id" ]; then
    SSH_COPY_ID=true
else
    SSH_COPY_ID=false
fi

# Set variables
SSH_USER=$1
SSH_HOST=$2
PUBLIC_PATH=$3

SSH_LOGIN="$SSH_USER@$SSH_HOST"
PATH_TO_WP_CONFIG="$PUBLIC_PATH/wp-config.php"

# Assert that we can ssh in
check_ssh "$SSH_LOGIN"
CAN_SSH_IN=$?

# If the --ssh-copy-id flag is set, copy the public key to the remote server and try again
if [ "$CAN_SSH_IN" -ne 0 ]; then
  if [ "$SSH_COPY_ID" = true ]; then
      assert_command_exists ssh-copy-id
      echo "Copying public key to $SSH_LOGIN"
      ssh-copy-id "$SSH_LOGIN" > /dev/null 2>&1
      check_ssh "$SSH_LOGIN"
      CAN_SSH_IN=$?
  fi
fi

if [ "$CAN_SSH_IN" -ne 0 ]; then
    echo "Could not connect to $SSH_LOGIN. Please set up public key authentication."
    exit 1
fi

# Assert that we can ssh in, and the wp-config.php file exists on the remote server
# Read the contents of the wp-config.php file
WP_CONFIG=$(ssh "$SSH_LOGIN" "cat $PATH_TO_WP_CONFIG")

# Print an error if the wp-config.php file doesn't exist
if [ -z "$WP_CONFIG" ]; then
    echo "Error: wp-config.php file not found at $PATH_TO_WP_CONFIG"
    exit 1
fi

# Get the database credentials from the wp-config.php file
DB_NAME=$(echo "$WP_CONFIG" | grep DB_NAME | cut -d \' -f 4)
DB_USER=$(echo "$WP_CONFIG" | grep DB_USER | cut -d \' -f 4)
DB_PASSWORD=$(echo "$WP_CONFIG" | grep DB_PASSWORD | cut -d \' -f 4)

# Assert that we can connect to the database
CAN_CONNECT_TO_DB=$(ssh "$SSH_LOGIN" "mysql -u $DB_USER -p$DB_PASSWORD -e 'show databases;' 2> /dev/null | grep $DB_NAME")

# Check that CAN_CONNECT_TO_DB matches the database name
if [ "$CAN_CONNECT_TO_DB" != "$DB_NAME" ]; then
    echo "Error: Could not connect to database $DB_NAME"
    exit 1
fi

# Create a temporary directory to download everything to
TMP_DIR=$(mktemp -d -t migrate-to-localwp-XXXXX)

# Copy the entire public directory to the temporary directory
echo "Copying files"
rsync -az --info=progress2 -e ssh "$SSH_LOGIN:$PUBLIC_PATH" "$TMP_DIR"

# Copy the database to the temporary directory
mkdir "$TMP_DIR/database"
echo "Copying database"
ssh "$SSH_LOGIN" "mysqldump --no-tablespaces -u $DB_USER -p$DB_PASSWORD $DB_NAME" 2> /dev/null > "$TMP_DIR/database/$DB_NAME.sql"

# Now zip up the temporary directory and place it in the working directory
WORKDIR=$(pwd)
cd "$TMP_DIR" || exit
echo "Zipping files to $WORKDIR/migrate-to-localwp-$SSH_USER.zip"
zip -r -q "$WORKDIR/migrate-to-localwp-$SSH_USER.zip" .
cd "$WORKDIR" || exit

# Remove the temporary directory
rm -rf "$TMP_DIR"

echo "Finished!"
exit 0
