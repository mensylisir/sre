package cmd
import ("bufio"; "fmt"; "os"; "strings")
func confirmAction(prompt string) error {
	if assumeYes { return nil }
	fmt.Printf("\n!!! WARNING: %s !!!\n> Type 'yes' to confirm: ", prompt)
	reader := bufio.NewReader(os.Stdin); input, _ := reader.ReadString('\n')
	if strings.TrimSpace(input) != "yes" { return fmt.Errorf("action cancelled") }
	return nil
}
