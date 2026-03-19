package main

import (
	"fmt"
	"strings"
)

func main() {
	info := collect()
	left, right := logo(), infoLines(info)
	pad := strings.Repeat(" ", logoWidth)

	for i := range max(len(left), len(right)) {
		l, r := pad, ""
		if i < len(left) {
			l = left[i]
		}
		if i < len(right) {
			r = right[i]
		}
		fmt.Printf("%s   %s\n", l, r)
	}
	fmt.Println()
}
