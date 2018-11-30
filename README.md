# tm35-format

The text format used between all [TM35-Metronome](https://github.com/TM35-Metronome) tools.

## Format

The format is line based and each line can be parsed by the following grammar:
```
Line <- Suffix* '=' .*

Suffix
   <- '.' IDENTIFIER
    / '[' INTEGER ']'

INTEGER <- [0-9]+
IDENTIFIER <- [a-zA-Z][A-Za-z0-9_]*
```
