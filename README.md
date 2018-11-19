# tm35-format

The text format used between all [TM35-Metronome](https://github.com/TM35-Metronome) tools.

## Format

The format is line based and each line can be parsed by the following grammar:
```
Line
    <- IDENTIFIER Suffix* EQUAL .*
     / COMMENT

Suffix
   <- DOT IDENTIFIER
    / LBRACKET INTEGER RBRACKET

COMMENT <- ws '#' .*
INTEGER <- ws [0-9]+
IDENTIFIER <- ws [a-zA-Z][A-Za-z0-9_]*
STAR <- ws '*'
DOT <- ws '.'
EQUAL <- ws '='
LBRACKET <- ws '['
RBRACKET <- ws ']'

ws <- [ \t]*
```
