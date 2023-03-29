#!/bin/bash

usage() {
cat << EOF

Usage: $0 [ -c ] [ -u url ] ssh-user ssh-host public-path
Package WordPress site files and database into a zip file.

-c           Automatically copy public key to remote server using ssh-copy-id

-u           The public url of the site. This optional flag is used to generate a phpinfo file that can
             automatically detect some site settings.

ssh-user     SSH user to connect to remote server

ssh-host     SSH host to connect to remote server

public-path  Path to WordPress public directory on remote server

EOF
}

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

generate_php_file() {
    PHP_FILE=$(cat << "EOF"
<?php

// Connect to mysql and get the mysql version
$link = mysqli_connect('localhost', '{{db_user}}', '{{db_pass}}', '{{db_name}}');
$mysqlVersion = mysqli_get_server_info($link);
mysqli_close($link);

// Get the server name and version
preg_match('/^(apache|nginx)\/(\d+\.\d+\.\d+).*/', strtolower($_SERVER['SERVER_SOFTWARE']), $matches);
$serverJson = isset($matches[1], $matches[2]) ? [ $matches[1] => [ 'name' => $matches[1], 'version' => $matches[2] ] ] : '';

// Get the current WordPress version by reading the wp-includes/version.php file
$wpVersionFile = file_get_contents(__DIR__ . DIRECTORY_SEPARATOR . 'wp-includes' . DIRECTORY_SEPARATOR .  'version.php');
preg_match('/\$wp_version = \'(.*)\';/', $wpVersionFile, $matches);
$wpVersion = isset($matches[1]) ? $matches[1] : '';

header('Content-Type: application/json');
echo json_encode(array_merge_recursive([
    'name' => 'Migrated Site',
    'domain' => '{{domain}}',
    'path' => '{{path}}',
    'wpVersion' => $wpVersion,
    'services' => [
        'php' => [
            'name' => 'php',
            'version' => PHP_VERSION,
        ],
        'mysql' => [
            'name' => 'mysql',
            'version' => $mysqlVersion,
        ],
    ],
], ['services' => $serverJson]));
EOF
    )

    # Replace the database credentials
    PHP_FILE=$(echo "$PHP_FILE" | sed "s/{{db_name}}/$1/g")
    PHP_FILE=$(echo "$PHP_FILE" | sed "s/{{db_user}}/$2/g")
    PHP_FILE=$(echo "$PHP_FILE" | sed "s/{{db_pass}}/$3/g")
    PHP_FILE=$(echo "$PHP_FILE" | sed "s*{{domain}}*$4*g")
    PHP_FILE=$(echo "$PHP_FILE" | sed "s*{{path}}*$5*g")

    echo "$PHP_FILE"
}

# Parse command line options
while getopts 'cu:' OPTION
do
  case "${OPTION}" in
    c) SSH_COPY_ID=1;;
    u) PUBLIC_URL="${OPTARG}";;
    *) usage
       exit 1
       ;;
  esac
done
shift $((OPTIND - 1))

# Assert all arguments are present
if [ "$#" -ne 3 ]; then
    usage
    exit 1
fi

# Create some whitespace
echo ""
echo ""

# Assert that all required commands are installed
REQUIRED_COMMANDS=(ssh rsync zip echo cut grep mkdir mktemp pwd cd curl)
for COMMAND in "${REQUIRED_COMMANDS[@]}"
do
    assert_command_exists "$COMMAND"
done

# Set variables
SSH_USER=$1
SSH_HOST=$2
PUBLIC_PATH=$3

SSH_LOGIN="$SSH_USER@$SSH_HOST"
PATH_TO_WP_CONFIG="$PUBLIC_PATH/wp-config.php"

# Assert that we can ssh in
check_ssh "$SSH_LOGIN"
CAN_SSH_IN=$?

# If the -c (ssh-copy-id) flag is set, copy the public key to the remote server and try again
if [ "$CAN_SSH_IN" -ne 0 ]; then
  if [ "$SSH_COPY_ID" = 1 ]; then
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

# Create a phpinfo file if the -u flag is set
if [ -n "$PUBLIC_URL" ]; then
    # Create a random file name
    FILENAME="migrate-to-localwp-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1).php"

    # Create a php file locally
    generate_php_file "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$PUBLIC_URL" "$PUBLIC_PATH" > "$TMP_DIR/$FILENAME"
    # Upload the php file to the remote server
    echo "Uploading php file"
    rsync -az --info=progress2 -e ssh "$TMP_DIR/$FILENAME" "$SSH_LOGIN:$PUBLIC_PATH/$FILENAME"
    # Delete the php file locally
    rm "$TMP_DIR/$FILENAME"

    # Store the JSON output by the info file
    JSON=$(curl -s "$PUBLIC_URL/$FILENAME")

    # Delete the php file on the remote server
    ssh "$SSH_LOGIN" "rm $PUBLIC_PATH/$FILENAME"

    # Generate the JSON file
    echo "Generating JSON file"
    # File must be named wpmigrate-export.json for Local to recognize it
    echo "$JSON" > "$TMP_DIR/wpmigrate-export.json"
fi

# Now zip up the temporary directory and place it in the working directory
WORKDIR=$(pwd)
cd "$TMP_DIR" || exit
echo "Zipping files and putting everything in the current directory"
zip -r -q "$WORKDIR/migrate-to-localwp-$SSH_USER.zip" .
cd "$WORKDIR" || exit

# Remove the temporary directory
rm -rf "$TMP_DIR"

echo "Finished!"
exit 0
