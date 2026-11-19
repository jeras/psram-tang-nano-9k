#!/usr/bin/env python3

if __name__ == "__main__":
    with open("incrementing_lines.txt", "w") as file:
        for page in range(304):
            for word in range(64//2):
                file.write(f"P{page:03}W{(word*2):02}\n")
