# Copyright (c) 1999 Greg Bartels. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.


BEGIN { $| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}
use Hardware::Simulator
   qw ( NewSignal Responder Repeater SimTime EventLoop TickEvent Finish );
$loaded = 1;
print "ok 1\n";

######################### End of black magic.


my @fifo;
eval {
NewSignal(my $in_clk,1);
NewSignal(my $in_data,1);
NewSignal(my $out_clk,0);
Repeater ( 10,sub{if ( $in_clk==0) { $in_clk=1;} else { $in_clk=0;}});
Repeater (33, sub{if ($out_clk==0) {$out_clk=1;} else {$out_clk=0;}});

Responder ( $in_clk,  sub
{
	unless (TickEvent($in_clk) and ($in_clk)) {return;}

	$in_data++;
	push(@fifo,$in_data);

	if (scalar(@fifo) > 20)
		{die "fifo reached maximum"; }
});

Responder ( $out_clk,  sub
{
	unless (TickEvent($out_clk) and ($out_clk)) {return;}
	shift(@fifo);
});

EventLoop();
};

if ($@  =~ /^fifo reached maximum/) 
  {print "ok 2 \n"; } 
else 
  {print "Fail 2 \n"; print $@; }

my $bottom = shift(@fifo);
my $top = pop(@fifo);
my $time = SimTime();


if ($top    ==  29) {print "ok 3 \n";} else {print "Fail 3\n";}
if ($bottom ==   9) {print "ok 4 \n";} else {print "Fail 4\n";}
if ($time   == 560) {print "ok 5 \n";} else {print "Fail 5\n";}
