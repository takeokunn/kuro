#!/usr/bin/env bash
# kuro-stress-colors.sh - Rapid full-screen colored output (asciiaquarium surrogate)
# Each cell gets its own ANSI color — worst-case face_ranges for the render pipeline.
exec perl - "$@" <<'PERL'
use strict;
use warnings;

my $rows  = $ENV{LINES}   // 24;
my $cols  = $ENV{COLUMNS} // 80;
my $delay = 0.08;          # ~12fps

my @chars = ('A'..'Z', 'a'..'z', '0'..'9', '*', '+', '-', '~', '#', '@', '%');

my $frame = 0;
while (1) {
    # Home + clear
    print "\033[H\033[2J";

    for my $row (1 .. $rows) {
        for my $col (1 .. $cols) {
            my $fg  = 31 + ($frame + $row + $col)     % 15;
            my $bg  = 41 + ($frame + $row*2 + $col*3) % 7;
            my $ch  = $chars[($frame + $col + $row) % scalar @chars];
            print "\033[${fg};${bg}m$ch";
        }
        print "\033[0m\n";
    }

    $frame = ($frame + 1) % 256;
    select(undef, undef, undef, $delay);
}
PERL
