package wp_package

import (
	"errors"
	"fmt"
	"github.com/jfortunato/migrate-to-localwp/internal/sftp"
	"github.com/spf13/cobra"
	"os"
	"regexp"
	"strings"
)

// var Verbose bool
var Username string
var Password string

var rootCmd = &cobra.Command{
	Use:     "wp-package [flags] HOST:DEST",
	Version: "0.0.1",
	Short:   "Export an existing WordPress site",
	Long: `Generate a complete archive of a WordPress site's files
	and database, which can be used to migrate the site
	to another host or to create a local development environment.`,
	//Args:      cobra.MatchAll(cobra.ExactArgs(1), cobra.OnlyValidArgs),
	//Args: cobra.ExactArgs(1),
	Args: func(cmd *cobra.Command, args []string) error {
		// Must have exactly one argument
		if len(args) != 1 {
			return errors.New("requires exactly one argument")
		}

		// Must have exactly one colon in the argument
		if strings.Count(args[0], ":") != 1 {
			return errors.New("missing colon in argument")
		}

		return nil
	},
	Run: func(cmd *cobra.Command, args []string) {
		//credentials := src.SSHCredentials{User: args[0], Pass: args[1], Host: args[2], Port: "22"}
		//[USER@]HOST:DEST

		// Split the first agument on the : character
		//host, path := splitHostPath(args[0])
		s := strings.Split(args[0], ":")
		host := s[0]
		path := s[1]

		credentials := sftp.SSHCredentials{User: Username, Pass: Password, Host: host, Port: "22"}

		fmt.Println(credentials)
		fmt.Println(path)

		sftp.EchoConfig(credentials, path)
	},
}

func init() {
	//rootCmd.PersistentFlags().BoolVarP(&Verbose, "verbose", "v", false, "verbose output")
	rootCmd.Flags().StringVarP(&Username, "username", "u", "", "SFTP username (required)")
	rootCmd.Flags().StringVarP(&Password, "password", "p", "", "SFTP password (required)")
	rootCmd.MarkFlagRequired("username")
	rootCmd.MarkFlagRequired("password")

	//./node_modules/.bin/tsc && node ./build/cli.js njarthurmurray castleblack-sp.everyhostservice.com /srv/users/njarthurmurray/apps/njarthurmurray-com/public/ -p xh7P46XD3pZCcZz3
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func splitHostPath(hostPath string) (string, string) {
	// Split the first agument on the : character
	re := regexp.MustCompile(`(.+):(.+)`)
	matches := re.FindStringSubmatch(hostPath)

	if len(matches) != 3 {
		panic(errors.New("Invalid host path"))
	}

	return matches[1], matches[2]
}
