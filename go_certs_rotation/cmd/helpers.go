package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// confirmAction prompts the user for confirmation before proceeding with a dangerous action.
// It returns an error if the user does not confirm.
func confirmAction(prompt string) error {
	if assumeYes {
		fmt.Printf("'%s' prompt skipped due to --yes flag.\n", prompt)
		return nil
	}

	fmt.Printf("\n!!! WARNING: %s !!!\n", prompt)
	fmt.Print("This is a potentially disruptive action. Please type 'yes' to confirm: ")

	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')

	if strings.TrimSpace(input) != "yes" {
		return fmt.Errorf("action cancelled by user")
	}

	return nil
}
