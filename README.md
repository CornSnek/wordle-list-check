# Wordle List Check
CLI tool to add wordle words and Wordle rules to filter words in the list for the game [Wordle](https://www.nytimes.com/games/wordle/index.html).

## Usage
This uses and requires Zig Version `0.14.0` or `0.14.1`

Use `zig build -Doptimize=ReleaseFast` to build the binary.

## words.txt
A `words.txt` file inside the binary path can be used to add potential words instead of manually adding each word in the tool.

Each word must be split with spaces or lines. For example:
```
WORDS
SPLIT
USING
LINES
```

Words can be case-insensitive, and will always output as uppercase.

## Rules usage
There are 3 types of Wordle rules to filter words.
* `e (letter)` - This filter excludes any words that contain this letter.
* `n (letter)1-5` - This filter excludes words that have this letter in this position from 1 to 5, **OR** doesn't contain this letter in any other position.
* `p (letter)1-5` - This filter includes only words that have this letter **AND** must be in this position from 1 to 5.

For example, the rule `p A5` is read as a word that has the letter `A`, and must be in position 5. `n B1` is read as a word that has the letter `B`, but must not be in position 1.