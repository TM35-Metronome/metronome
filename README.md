# tm35-format

The text format used between all [TM35-Metronome](https://github.com/TM35-Metronome) tools.

## Format

The format is line based and each line can be parsed by the following grammar:
```
Line
    <- ws IDENTIFIER Suffix* EQUAL .*
     / ws COMMENT

Suffix
   <- DOT [a-zA-Z][A-Za-z0-9_]*
    / LBRACKET INTEGER RBRACKET

COMMENT <- '#' .*
INTEGER <- [0-9]+ ws
IDENTIFIER <- [a-zA-Z][A-Za-z0-9_]* ws
STAR <- '*' ws
DOT <- '.' ws
EQUAL <- '=' ws
LBRACKET <- '[' ws
RBRACKET <- ']' ws

ws <- [ \t]*
```
