package sftp

import (
	"bytes"
	"errors"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
	"io"
	"log"
	"net"
	"regexp"
)

type SSHCredentials struct {
	User string
	Pass string
	Host string
	Port string
}

type WpConfigFields struct {
	dbName string
	dbUser string
	dbPass string
	dbHost string
}

func EchoConfig(credentials SSHCredentials, pathToPublic string) {
	// Set up the config
	config := &ssh.ClientConfig{
		User:            credentials.User,
		Auth:            []ssh.AuthMethod{ssh.Password(credentials.Pass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}

	// Set up the connection
	conn, err := ssh.Dial("tcp", net.JoinHostPort(credentials.Host, credentials.Port), config)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	//var conn *ssh.Client

	// open an SFTP session over an existing ssh connection.
	client, err := sftp.NewClient(conn)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	// Read the wp-config file
	file, err := client.Open(pathToPublic + "wp-config.php")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	// Read the file
	var b bytes.Buffer
	_, err = io.Copy(&b, file)
	if err != nil {
		log.Fatal(err)
	}

	//fmt.Println(b.String())
	log.Println(b.String())

	//// List the directory contents
	//files, err := client.ReadDir(pathToPublic)
	//if err != nil {
	//	log.Fatal(err)
	//}
	//
	//for _, file := range files {
	//	log.Println(file.Name())
	//}

	//// walk a directory
	//w := client.Walk(pathToPublic)
	//for w.Step() {
	//	if w.Err() != nil {
	//		continue
	//	}
	//	log.Println(w.Path())
	//}

	//output, err := remoteRun(SSHCredentials{user, pass, host, "22"}, "cat "+pathToPublic+"wp-config.php")
	//if err != nil {
	//	fmt.Println(err)
	//	return
	//}
	//fmt.Println(output)
	//
	//// Parse the fields from the wp-config.php file
	////dbName, err := parseWpConfigField(output, "DB_NAME")
	////if err != nil {
	////	panic(err)
	////}
	////dbUser, err := parseWpConfigField(output, "DB_USER")
	////if err != nil {
	////	panic(err)
	////}
	//
	//fields, err := getWpConfigFields(output)
	//fmt.Println(fields)
	//
	////fmt.Println("DB_NAME: " + dbName)
	////fmt.Println("DB_USER: " + dbUser)
}

func getWpConfigFields(wpConfig string) (WpConfigFields, error) {
	dbName, err := parseWpConfigField(wpConfig, "DB_NAME")
	if err != nil {
		return WpConfigFields{}, err
	}
	dbUser, err := parseWpConfigField(wpConfig, "DB_USER")
	if err != nil {
		return WpConfigFields{}, err
	}
	dbPass, err := parseWpConfigField(wpConfig, "DB_PASSWORD")
	if err != nil {
		return WpConfigFields{}, err
	}
	dbHost, err := parseWpConfigField(wpConfig, "DB_HOST")
	if err != nil {
		return WpConfigFields{}, err
	}

	return WpConfigFields{dbName, dbUser, dbPass, dbHost}, nil
}

func parseWpConfigField(wpConfig, field string) (string, error) {
	re := regexp.MustCompile(`define\('` + field + `', '(.*)'\);`)
	matches := re.FindStringSubmatch(wpConfig)
	if len(matches) <= 1 {
		return "", errors.New("Could not find " + field + " in wp-config.php")
	}

	return matches[1], nil
}

func remoteRun(credentials SSHCredentials, cmd string) (output string, err error) {
	// Setup the config
	config := &ssh.ClientConfig{
		User:            credentials.User,
		Auth:            []ssh.AuthMethod{ssh.Password(credentials.Pass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}

	// Setup the client
	client, err := ssh.Dial("tcp", net.JoinHostPort(credentials.Host, credentials.Port), config)
	if err != nil {
		return
	}

	// Setup the session
	session, err := client.NewSession()
	if err != nil {
		return
	}
	defer session.Close()

	//var b bytes.Buffer
	//session.Stdout = &b
	//var b []byte

	b, err := session.Output(cmd)
	//output = b.String()

	return string(b), err
}

//// e.g. output, err := remoteRun("root", "MY_IP", "PRIVATE_KEY", "ls")
//func remoteRun(user string, addr string, privateKey string, cmd string) (string, error) {
//	// privateKey could be read from a file, or retrieved from another storage
//	// source, such as the Secret Service / GNOME Keyring
//	key, err := ssh.ParsePrivateKey([]byte(privateKey))
//	if err != nil {
//		return "", err
//	}
//	// Authentication
//	config := &ssh.ClientConfig{
//		User: user,
//		// https://github.com/golang/go/issues/19767
//		// as clientConfig is non-permissive by default
//		// you can set ssh.InsercureIgnoreHostKey to allow any host
//		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
//		Auth: []ssh.AuthMethod{
//			ssh.PublicKeys(key),
//		},
//		//alternatively, you could use a password
//		/*
//		   Auth: []ssh.AuthMethod{
//		       ssh.Password("PASSWORD"),
//		   },
//		*/
//	}
//	// Connect
//	client, err := ssh.Dial("tcp", net.JoinHostPort(addr, "22"), config)
//	if err != nil {
//		return "", err
//	}
//	// Create a session. It is one session per command.
//	session, err := client.NewSession()
//	if err != nil {
//		return "", err
//	}
//	defer session.Close()
//	var b bytes.Buffer  // import "bytes"
//	session.Stdout = &b // get output
//	// you can also pass what gets input to the stdin, allowing you to pipe
//	// content from client to server
//	//      session.Stdin = bytes.NewBufferString("My input")
//
//	// Finally, run the command
//	err = session.Run(cmd)
//	return b.String(), err
//}
