package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/joho/godotenv"
)

var (
	TEAM_WEBHOOK string
	IP_LIST_PATH string
)

func main() {
	// Load .env (optional)
	_ = godotenv.Load()

	TEAM_WEBHOOK = os.Getenv("TEAM_WEBHOOK")
	IP_LIST_PATH = os.Getenv("IP_LIST_PATH")

	if TEAM_WEBHOOK == "" {
		log.Println("TEAM_WEBHOOK is undefined.")
	}

	if IP_LIST_PATH == "" {
		log.Fatal("IP_LIST_PATH is undefined.")
	}

	file, err := os.Open(IP_LIST_PATH)
	if err != nil {
		log.Fatalf("error opening ip list: %v", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue // skip empty lines and comments
		}

		// Expect format: <ip> <alias>
		parts := strings.Fields(line)
		if len(parts) < 2 {
			log.Printf("invalid line: %s", line)
			continue
		}
		ip := parts[0]
		alias := strings.Join(parts[1:], " ")

		// Ping
		if !ping(ip) {
			log.Printf("Host unreachable: %s (%s)", alias, ip)
			if TEAM_WEBHOOK != "" {
				sendTeamsWebhook(alias, ip)
			}
		}
	}

	if err := scanner.Err(); err != nil {
		log.Fatalf("error reading file: %v", err)
	}
}

func ping(ip string) bool {
	cmd := exec.Command("ping", "-c", "1", "-W", "2", ip)
	err := cmd.Run()
	return err == nil
}

func sendTeamsWebhook(alias, ip string) {
	payload := fmt.Sprintf(`{
		"title": "Host Unreachable",
		"text": "**%s** (%s) is unreachable.",
		"themeColor": "FF0000"
	}`, alias, ip)

	cmd := exec.Command("curl", "-s", "-X", "POST", TEAM_WEBHOOK,
		"-H", "Content-Type: application/json",
		"-d", payload)
	err := cmd.Run()
	if err != nil {
		log.Printf("Failed to send webhook: %v", err)
	}
}
